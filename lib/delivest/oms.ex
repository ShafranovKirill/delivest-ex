defmodule Delivest.Oms do
  alias Delivest.Oms.{CartPromo, OrderRepeat, OrderService, Orders, Carts}

  defdelegate create_order(attrs, opts \\ []), to: OrderService
  defdelegate update_order(order, attrs, opts \\ []), to: Orders
  defdelegate update_payment_method(order, attrs, actor \\ :system), to: Orders
  defdelegate advance_order(order, to, by, opts \\ []), to: Orders
  defdelegate cancel_order(order, by, attrs), to: Orders
  defdelegate soft_delete_order(order, actor \\ :system), to: Orders
  defdelegate create_draft_cart(order), to: Orders
  defdelegate list_active_orders(session_id, client_id \\ nil), to: Orders
  defdelegate list_client_orders(client_id, branch_scope, limit \\ 50), to: Orders
  defdelegate count_client_orders(client_id), to: Orders

  defdelegate get_or_create_cart(opts), to: Carts
  defdelegate get_cart(opts), to: Carts
  defdelegate get_cart_by_id(cart_id, opts \\ []), to: Carts
  defdelegate create_cart(attrs), to: Carts
  defdelegate clear_cart(cart_id), to: Carts
  defdelegate add_item(cart_id, product_id, quantity \\ 1), to: Carts
  defdelegate repeat_order(cart_id, client_id, order_id), to: OrderRepeat, as: :run
  defdelegate remove_item(cart_id, product_id, opts \\ []), to: Carts
  defdelegate delete_cart(cart_or_id), to: Carts
  defdelegate detach_cart(cart_or_id), to: Carts
  defdelegate update_cart_context(cart_id, attrs), to: Carts, as: :update_context

  defdelegate apply_promo_code(cart_id, code), to: CartPromo, as: :apply_code
  defdelegate remove_promo_code(cart_id), to: CartPromo, as: :remove_code
  defdelegate set_cart_fulfillment(cart_id, fulfillment_type), to: CartPromo, as: :set_fulfillment
  defdelegate bind_cart_client(cart_view, client_id), to: CartPromo, as: :bind_client
end
