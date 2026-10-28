defmodule DelivestWeb.Plugs.FetchCurrentClient do
  @behaviour Plug
  import Plug.Conn

  alias Delivest.Identity
  alias DelivestWeb.ClientToken
  alias DelivestWeb.Helpers.ApiError

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with token when is_binary(token) <- bearer_token(conn),
         true <- Identity.client_auth_enabled?() do
      authenticate(conn, token)
    else
      _ -> assign(conn, :current_client, nil)
    end
  end

  defp authenticate(conn, token) do
    with {:ok, client_id} <- ClientToken.verify_access(token),
         {:ok, client} <- Identity.fetch_authenticated_client(client_id) do
      assign(conn, :current_client, client)
    else
      _ ->
        conn
        |> ApiError.send_error(:unauthorized, :unauthorized, "Invalid or expired token")
        |> halt()
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> token
      _ -> nil
    end
  end
end
