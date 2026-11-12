defmodule DelivestWeb.Test.ProductPickerHost do
  use DelivestWeb, :live_view

  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       products: session["products"],
       mode: session["mode"],
       selected_ids: session["selected_ids"] || [],
       open: true,
       result: nil
     )}
  end

  def handle_event("refresh", _, socket), do: {:noreply, assign(socket, refreshed: true)}
  def handle_event("open", _, socket), do: {:noreply, assign(socket, open: true)}

  def handle_info({:saved, ids}, socket), do: {:noreply, assign(socket, open: false, result: ids)}
  def handle_info(:cancelled, socket), do: {:noreply, assign(socket, open: false)}

  def render(assigns) do
    ~H"""
    <div>
      <button id="open-picker" phx-click="open">Open</button>
      <button id="refresh-host" phx-click="refresh">Refresh</button>
      <div id="picker-result">{inspect(@result)}</div>
      <.live_component
        :if={@open}
        module={DelivestWeb.Staff.ProductLive.ProductPicker}
        id="test-picker"
        products={@products}
        selected_ids={@selected_ids}
        mode={@mode}
        on_save={fn ids -> send(self(), {:saved, ids}) end}
        on_cancel={fn -> send(self(), :cancelled) end}
      />
    </div>
    """
  end
end
