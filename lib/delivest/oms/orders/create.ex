defmodule Delivest.Oms.Orders.Create do
  alias Delivest.Audit
  alias Delivest.Oms.{Carts, Order}
  alias Delivest.Oms.Order.OrderNumber
  alias Delivest.Oms.Orders.{Assembler, Attrs, CartGuard, ClientResolver, Lines, Notifier}
  alias Delivest.Repo
  alias Ecto.Multi

  def run(attrs, opts \\ []) do
    attrs = Attrs.normalize(attrs)
    after_insert = Keyword.get(opts, :after_insert, & &1)
    client_opts = [update_existing: Keyword.get(opts, :update_client, true)]

    Multi.new()
    |> Multi.run(:client_id, fn _, _ -> ClientResolver.resolve(attrs, client_opts) end)
    |> Multi.run(:cart, fn _, _ -> CartGuard.acquire(attrs["cart_id"], attrs["branch_id"]) end)
    |> Multi.run(:lines, fn _, %{cart: cart} -> Lines.from_cart(cart) end)
    |> Multi.run(:number, fn _, _ -> OrderNumber.generate() end)
    |> Multi.insert(:order, &Assembler.changeset(%Order{}, own_attrs(attrs, &1), &1))
    |> after_insert.()
    |> Multi.run(:detached_cart, fn _, %{cart: cart} -> Carts.detach_cart(cart) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order}} -> Notifier.publish({:ok, order}, [:order, :created])
      {:error, step, reason, _} -> {:error, step, reason}
    end
    |> track(opts)
  end

  defp track(result, opts) do
    actor = Keyword.get_lazy(opts, :actor, fn -> customer(result) end)
    Audit.track(result, actor, "order.created")
  end

  defp customer({:ok, %Order{client: client}}), do: client
  defp customer(_result), do: nil

  defp own_attrs(attrs, %{number: number, cart: cart}) do
    attrs
    |> Map.put("number", number)
    |> Map.put_new("staff_id", cart.staff_id)
  end
end
