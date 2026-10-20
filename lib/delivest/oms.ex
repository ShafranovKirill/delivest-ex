defmodule Delivest.Oms do
  alias Delivest.Oms.{OrderService, Orders, Carts}

  defdelegate create_order(attrs, opts \\ []), to: OrderService
  defdelegate update_order(order, attrs, opts \\ []), to: Orders
  defdelegate update_order_details(order, attrs, actor \\ :system), to: Orders
  defdelegate soft_delete_order(order, actor \\ :system), to: Orders
  defdelegate create_draft_cart(order), to: Orders
  defdelegate list_active_orders(session_id, client_id \\ nil), to: Orders
  defdelegate list_client_orders(client_id, branch_scope, limit \\ 50), to: Orders

  defdelegate get_or_create_cart(opts), to: Carts
  defdelegate get_cart(opts), to: Carts
  defdelegate get_cart_by_id(cart_id, opts \\ []), to: Carts
  defdelegate create_cart(attrs), to: Carts
  defdelegate clear_cart(cart_id), to: Carts
  defdelegate add_item(cart_id, product_id, quantity \\ 1), to: Carts
  defdelegate remove_item(cart_id, product_id, opts \\ []), to: Carts
  defdelegate delete_cart(cart_or_id), to: Carts
  defdelegate detach_cart(cart_or_id), to: Carts
end
