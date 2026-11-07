defmodule DelivestWeb.OrdersChannel do
  use DelivestWeb, :channel

  alias Delivest.Oms.{OrderFlow, Orders}
  alias DelivestWeb.Client.Order.OrderJSON

  @impl true
  def join("orders", _params, socket) do
    Orders.subscribe_owner(:session, socket.assigns.session_id)
    Orders.subscribe_owner(:client, socket.assigns.client_id)
    {:ok, assign(socket, last_pushed: nil)}
  end

  @impl true
  def handle_info({:client_order, order}, socket) do
    if Orders.owned_by?(order, socket.assigns.session_id, socket.assigns.client_id) do
      payload = %{
        v: 1,
        order: OrderJSON.active_order_data(order),
        active: OrderFlow.active?(order)
      }

      if payload == socket.assigns.last_pushed do
        {:noreply, socket}
      else
        push(socket, "order", payload)
        {:noreply, assign(socket, last_pushed: payload)}
      end
    else
      {:noreply, socket}
    end
  end
end
