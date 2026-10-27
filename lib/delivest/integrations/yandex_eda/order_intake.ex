defmodule Delivest.Integrations.YandexEda.OrderIntake do
  alias Delivest.Integrations.YandexEda.{
    Menu,
    OrderAttrs,
    OrderConfirmation,
    OrderLookup,
    OrderRequest,
    Places,
    StopList
  }

  alias Delivest.Oms
  alias Delivest.Oms.Order

  def create(%OrderRequest{} = request) do
    case OrderLookup.by_eats_id(request.eats_id) do
      %Order{} = order -> {:ok, order}
      nil -> place(request)
    end
  end

  defp place(request) do
    with {:ok, branch, settings} <- Places.fetch(request.restaurant_id),
         :ok <- ensure_available(branch, settings, request.items),
         {:ok, cart} <- fill_cart(branch.id, request.items) do
      request
      |> OrderAttrs.build(cart, branch, settings)
      |> Oms.create_order(OrderAttrs.opts(request, branch, settings))
      |> settle(request)
      |> tap(&watch_deadline/1)
    end
  end

  defp ensure_available(branch, settings, items) do
    offered = MapSet.new(Menu.product_ids(branch, settings))
    StopList.refresh(branch.id)
    stopped = MapSet.new(StopList.unavailable(branch.id, Enum.map(items, & &1.product_id)))

    case Enum.filter(items, &(&1.product_id in stopped or &1.product_id not in offered)) do
      [] -> :ok
      unavailable -> {:error, {:unavailable, unavailable}}
    end
  end

  defp fill_cart(branch_id, items) do
    with {:ok, cart} <- Oms.create_cart(%{branch_id: branch_id}),
         {:ok, cart} <-
           Oms.Carts.add_items(cart.id, Enum.map(items, &{&1.product_id, &1.quantity})) do
      if length(cart.items) == length(items),
        do: {:ok, cart},
        else: {:error, {:unavailable, items}}
    end
  end

  defp watch_deadline({:ok, %Order{status: :created} = order}), do: OrderConfirmation.watch(order)
  defp watch_deadline(_result), do: :ok

  defp settle({:ok, order}, _request), do: {:ok, order}

  defp settle({:error, :order, %Ecto.Changeset{} = changeset}, request) do
    case OrderLookup.by_eats_id(request.eats_id) do
      %Order{} = order -> {:ok, order}
      nil -> {:error, changeset}
    end
  end

  defp settle({:error, _step, reason}, _request), do: {:error, reason}
  defp settle(error, _request), do: error
end
