defmodule DelivestWeb.ClientSocket do
  use Phoenix.Socket

  alias DelivestWeb.ClientToken

  channel "orders", DelivestWeb.OrdersChannel
  channel "auth:*", DelivestWeb.AuthChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    case ClientToken.verify_socket(token) do
      {:ok, %{session_id: session_id, client_id: client_id}} ->
        {:ok, assign(socket, session_id: session_id, client_id: client_id)}

      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(_socket), do: nil
end
