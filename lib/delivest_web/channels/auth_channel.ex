defmodule DelivestWeb.AuthChannel do
  use DelivestWeb, :channel

  alias Delivest.Identity
  alias Delivest.Identity.{ClientAuth, PhoneConfirmations}
  alias DelivestWeb.Client.Auth.AuthJSON
  alias DelivestWeb.ClientToken

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
    case Identity.complete_client_auth(socket.assigns.confirmation_id, socket.assigns.session_id) do
      {:ok, client} ->
        %{data: session} =
          AuthJSON.session(%{client: client, tokens: ClientToken.issue(client.id)})

        push(socket, "confirmed", session)
        {:stop, :normal, socket}

      {:error, :pending} ->
        {:noreply, socket}

      {:error, reason} ->
        push(socket, "failed", %{code: code(reason)})
        {:stop, :normal, socket}
    end
  end

  defp code(:client_blocked), do: "client_blocked"
  defp code(_reason), do: "confirmation_not_found"
end
