defmodule DelivestWeb.AuthChannel do
  use DelivestWeb, :channel

  alias Delivest.Identity.{ClientAuth, PhoneConfirmations}

  @impl true
  def join("auth:" <> confirmation_id, _params, socket) do
    if PhoneConfirmations.pending?(confirmation_id, socket.assigns.session_id) do
      ClientAuth.subscribe(confirmation_id)
      send(self(), :phone_confirmed)
      {:ok, assign(socket, confirmation_id: confirmation_id)}
    else
      {:error, %{code: "confirmation_not_found"}}
    end
  end

  @impl true
  def handle_info(:phone_confirmed, socket) do
    if PhoneConfirmations.confirmed?(socket.assigns.confirmation_id, socket.assigns.session_id) do
      push(socket, "confirmed", %{})
      {:stop, :normal, socket}
    else
      {:noreply, socket}
    end
  end
end
