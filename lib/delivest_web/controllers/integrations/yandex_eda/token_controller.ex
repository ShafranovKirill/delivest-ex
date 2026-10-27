defmodule DelivestWeb.Integrations.YandexEda.TokenController do
  use DelivestWeb, :controller

  alias Delivest.Integrations.YandexEda
  alias DelivestWeb.Integrations.YandexEda.Reply

  def create(conn, %{
        "client_id" => id,
        "client_secret" => secret,
        "grant_type" => "client_credentials"
      }) do
    case YandexEda.issue_token(id, secret) do
      {:ok, token} ->
        json(conn, %{
          access_token: token,
          token_type: "bearer",
          expires_in: YandexEda.Token.max_age()
        })

      {:error, :invalid_client} ->
        Reply.errors(conn, :bad_request, :invalid_client, "Invalid client_id or client_secret")
    end
  end

  def create(conn, _params),
    do:
      Reply.errors(
        conn,
        :bad_request,
        :bad_request,
        "client_id, client_secret and grant_type=client_credentials are required"
      )
end
