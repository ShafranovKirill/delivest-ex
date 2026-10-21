defmodule DelivestWeb.Staff.OrderLive.OrderDraft do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.{Identity, Oms}
  alias Delivest.Oms.{CartView, Order, Orders}

  def new(staff, branch_id) do
    {:ok, cart} = Oms.get_or_create_cart(staff_id: staff.id, branch_id: branch_id)
    %{order: %Order{customer_phone: "+7"}, cart: cart, title: gettext("New Order")}
  end

  def edit(order, connected?) do
    %{
      order: with_customer(order),
      cart: edit_cart(order, connected?),
      title: gettext("Edit Order #%{number}", number: order.number)
    }
  end

  def fetch_editable(staff, branch_id, id) do
    with true <- Identity.can?(staff, "orders.update"),
         {:ok, uuid} <- Ecto.UUID.cast(id),
         %Order{branch_id: ^branch_id} = order <- Orders.get_order(uuid),
         false <- order.status == :crm do
      {:ok, order}
    else
      false -> {:error, gettext("Permission denied")}
      true -> {:error, gettext("CRM orders cannot be edited")}
      _ -> {:error, gettext("Order not found")}
    end
  end

  defp with_customer(%Order{client: %{phone: phone, name: name}} = order),
    do: %{order | customer_phone: phone, customer_name: name}

  defp with_customer(order), do: %{order | customer_phone: "+7"}

  defp edit_cart(order, true) do
    {:ok, cart} = Oms.create_draft_cart(order)
    cart
  end

  defp edit_cart(order, false), do: %CartView{branch_id: order.branch_id}
end
