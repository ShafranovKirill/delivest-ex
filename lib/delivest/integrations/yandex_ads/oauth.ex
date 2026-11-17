defmodule Delivest.Integrations.YandexAds.OAuth do
  alias Delivest.HTTP.Client

  def authorize_url(state) do
    with {:ok, client_id} <- config("CLIENT_ID"), {:ok, redirect} <- config("REDIRECT_URI") do
      {:ok,
       "https://oauth.yandex.ru/authorize?" <>
         URI.encode_query(%{
           response_type: "code",
           client_id: client_id,
           redirect_uri: redirect,
           state: state,
           scope: "direct:api metrika:read metrika:write metrika:offline_data"
         })}
    end
  end

  def exchange(code) when is_binary(code) and byte_size(code) in 1..2048 do
    with {:ok, redirect} <- config("REDIRECT_URI"),
         do: token(%{grant_type: "authorization_code", code: code, redirect_uri: redirect})
  end

  def exchange(_), do: {:error, :invalid_code}

  def refresh(refresh_token) when is_binary(refresh_token),
    do: token(%{grant_type: "refresh_token", refresh_token: refresh_token})

  defp token(params) do
    with {:ok, client_id} <- config("CLIENT_ID"),
         {:ok, secret} <- config("CLIENT_SECRET"),
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

  defp config(key) do
    case System.get_env("YANDEX_ADS_OAUTH_" <> key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :oauth_not_configured}
    end
  end
end
