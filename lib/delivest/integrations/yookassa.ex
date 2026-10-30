defmodule Delivest.Integrations.Yookassa do
  alias Delivest.{Identity, Repo}
  alias Delivest.Integrations.Yookassa.{Api, Settings}

  def get_settings, do: Repo.one(Settings) || %Settings{}

  def change_settings(%Settings{} = settings, attrs \\ %{}),
    do: Settings.changeset(settings, attrs)

  def update_settings(staff, attrs) do
    if Identity.can?(staff, "admin"),
      do: get_settings() |> Settings.changeset(attrs) |> Repo.insert_or_update(),
      else: {:error, :forbidden}
  end

  def configured?, do: Settings.complete?(get_settings())

  def webhook_url(token),
    do: DelivestWeb.Endpoint.url() <> "/integrations/yookassa/" <> token

  def valid_webhook_token?(token) when is_binary(token) do
    case get_settings() do
      %Settings{webhook_token: expected} when is_binary(expected) ->
        Plug.Crypto.secure_compare(expected, token)

      _settings ->
        false
    end
  end

  def valid_webhook_token?(_token), do: false

  def health_check(%Settings{} = settings) do
    if Settings.complete?(settings) do
      case Api.me(settings) do
        {:ok, %{"account_id" => _id}} -> :ok
        {:ok, body} -> {:error, {:yookassa, body}}
        error -> error
      end
    else
      {:error, :yookassa_not_configured}
    end
  end

  def health_check(_settings), do: {:error, :yookassa_not_configured}

  def shop(%Settings{} = settings) do
    with {:ok, %{"account_id" => id} = body} <- Api.me(settings) do
      {:ok,
       %{
         account_id: id,
         test: body["test"] == true,
         enabled: body["status"] == "enabled",
         fiscalization: get_in(body, ["fiscalization", "provider"]),
         receipts_conflict: get_in(body, ["fiscalization", "enabled"]) == true
       }}
    end
  end
end
