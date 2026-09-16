defmodule Delivest.Oms do
  alias Delivest.Oms.{OrderService, Orders}
  defdelegate create_order(attrs), to: OrderService

  defdelegate update_order(order, attrs), to: Orders
  defdelegate soft_delete_order(order), to: Orders
end
