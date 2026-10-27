defmodule DelivestWeb.Plugs.YandexEdaAuth do
  import Plug.Conn

  alias Delivest.Integrations.YandexEda
  alias DelivestWeb.Integrations.YandexEda.Reply

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         true <- YandexEda.valid_token?(token) do
      conn
    else
      _ -> Reply.unauthorized(conn)
    end
  end
end
