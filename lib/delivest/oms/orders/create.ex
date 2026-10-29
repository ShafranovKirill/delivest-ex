defmodule Delivest.Oms.Orders.Create do
  alias Delivest.Audit
  alias Delivest.Oms.{Carts, Kitchen, Order}
  alias Delivest.Oms.Order.OrderNumber

  alias Delivest.Oms.Orders.{
    Assembler,
    Attrs,
    CartGuard,
    ClientResolver,
    DeliveryFee,
    Lines,
    Notifier,
    Pricing,
    StatusChange,
    StopGuard
  }

  alias Delivest.{Promo, Push, Repo}
  alias Ecto.Multi

  def run(attrs, opts \\ []) do
    attrs = Attrs.normalize(attrs)
    after_insert = Keyword.get(opts, :after_insert, & &1)
    client_opts = [update_existing: Keyword.get(opts, :update_client, true)]
    pricing = Keyword.get(opts, :pricing, &Pricing.run/3)

    Multi.new()
    |> Multi.run(:client_id, fn _, _ -> ClientResolver.resolve(attrs, client_opts) end)
    |> Multi.run(:cart, fn _, _ -> CartGuard.acquire(attrs["cart_id"], attrs["branch_id"]) end)
    |> Multi.run(:pricing, fn _, %{cart: cart, client_id: id} -> pricing.(cart, attrs, id) end)
    |> Multi.run(:stops, fn _, %{pricing: pricing, cart: cart} ->
      StopGuard.check(cart.branch_id, pricing)
    end)
    |> Multi.run(:delivery, fn _, %{pricing: pricing, cart: cart} ->
      DeliveryFee.run(cart.branch_id, attrs, pricing, opts)
    end)
    |> Multi.run(:lines, fn _, %{pricing: pricing} -> Lines.from_pricing(pricing) end)
    |> Multi.run(:number, fn repo, %{cart: cart} -> OrderNumber.next(repo, cart.branch_id) end)
    |> Multi.insert(:order, &build(attrs, &1, opts))
    |> Multi.run(:advanced, fn repo, %{order: order} -> advance(repo, order, opts[:advance]) end)
    |> Multi.run(:redemptions, fn _, %{order: order, pricing: pricing} ->
      Promo.redeem(order, pricing)
    end)
    |> after_insert.()
    |> Multi.run(:detached_cart, fn _, %{cart: cart} -> Carts.detach_cart(cart) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{advanced: order}} ->
        {:ok, order} = Notifier.publish({:ok, order}, [:order, :created])
        if order.status == :created, do: Push.notify_staff(:order_created, order.id)
        Kitchen.order_accepted(order)

      {:error, step, reason, _} ->
        {:error, step, reason}
    end
    |> track(opts)
  end

  defp advance(_repo, order, nil), do: {:ok, order}

  defp advance(repo, order, {to, by}) do
    with {:ok, %{order: order}} <- StatusChange.apply(repo, order, to, by), do: {:ok, order}
  end

  defp track(result, opts) do
    actor = Keyword.get_lazy(opts, :actor, fn -> customer(result) end)
    Audit.track(result, actor, "order.created")
  end

  defp customer({:ok, %Order{client: client}}), do: client
  defp customer(_result), do: nil

  defp build(attrs, changes, opts) do
    %Order{}
    |> Assembler.changeset(own_attrs(attrs, changes), changes)
    |> Order.source_changeset(Keyword.get(opts, :source, "app"))
    |> then(&if(opts[:channel], do: Order.channel_changeset(&1, opts[:channel]), else: &1))
    |> then(&if(opts[:crm], do: Order.crm_changeset(&1, opts[:crm]), else: &1))
    |> then(&if(opts[:paid_online], do: Order.paid_online_changeset(&1), else: &1))
  end

  defp own_attrs(attrs, %{number: number, cart: cart}) do
    attrs
    |> Map.merge(%{
      "number" => number.number,
      "daily_number" => number.daily_number,
      "business_date" => number.business_date
    })
    |> Map.put_new("staff_id", cart.staff_id)
  end
end
