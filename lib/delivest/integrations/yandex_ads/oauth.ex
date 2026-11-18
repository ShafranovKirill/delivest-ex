defmodule Delivest.Integrations.YandexAds.OAuth do
  alias Delivest.HTTP.Client
  alias Delivest.Integrations.YandexAds.Settings

  @callback_path "/staff/integrations/yandex-ads/callback"

  def redirect_uri, do: DelivestWeb.Endpoint.url() <> @callback_path

  def authorize_url(state, %Settings{} = settings) do
    with {:ok, client_id} <- configured(settings.oauth_client_id) do
      {:ok,
       "https://oauth.yandex.ru/authorize?" <>
         URI.encode_query(%{
           response_type: "code",
           client_id: client_id,
           redirect_uri: redirect_uri(),
           state: state,
           scope: "direct:api metrika:read metrika:write metrika:offline_data"
         })}
    end
  end

  def exchange(code, %Settings{} = settings)
      when is_binary(code) and byte_size(code) in 1..2048 do
    token(%{grant_type: "authorization_code", code: code, redirect_uri: redirect_uri()}, settings)
  end

  def exchange(_, _), do: {:error, :invalid_code}

  def refresh(refresh_token, %Settings{} = settings) when is_binary(refresh_token),
    do: token(%{grant_type: "refresh_token", refresh_token: refresh_token}, settings)

  defp token(params, settings) do
    with {:ok, client_id} <- configured(settings.oauth_client_id),
         {:ok, secret} <- configured(settings.oauth_client_secret),
         {:ok, %{status: 200, body: %{"access_token" => token} = body}} when is_binary(token) <-
           Client.post(
             "https://oauth.yandex.ru/token",
             Map.merge(params, %{client_id: client_id, client_secret: secret}),
             format: :form,
             journal: :yandex_ads,
             response: :full,
             retry: false
           ) do
      {:ok, body}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_token_response}
    end
  end

  defp configured(value) when is_binary(value) and value != "", do: {:ok, value}
  defp configured(_), do: {:error, :oauth_not_configured}
end
