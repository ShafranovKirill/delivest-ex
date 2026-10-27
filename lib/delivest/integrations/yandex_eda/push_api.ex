defmodule Delivest.Integrations.YandexEda.PushApi do
  alias Delivest.HTTP.Client
  alias Delivest.Integrations.YandexEda.Settings

  @base_url "https://dc-partner.eda.yandex.net"
  @cache :crm_cache
  @token_margin 60

  def reload_menu(%Settings{} = settings, restaurant_id, operation) do
    with {:ok, token} <- token(settings) do
      Client.post(
        "/menu/import/initiation",
        %{restaurantId: restaurant_id, operationType: operation},
        base_url: @base_url,
        headers: [{"authorization", "Bearer " <> token}, {"partner-name", settings.partner_name}]
      )
    end
  end

  def configured?(%Settings{} = settings),
    do:
      Enum.all?(
        [settings.partner_name, settings.push_client_id, settings.push_client_secret],
        &(&1 not in [nil, ""])
      )

  defp token(settings) do
    case Cachex.get(@cache, cache_key(settings)) do
      {:ok, token} when is_binary(token) -> {:ok, token}
      _ -> issue(settings)
    end
  end

  defp issue(settings) do
    "/oauth2/token"
    |> Client.post(
      [client_id: settings.push_client_id, client_secret: settings.push_client_secret],
      base_url: @base_url,
      format: :form
    )
    |> case do
      {:ok, %{"access_token" => token} = body} ->
        Cachex.put(@cache, cache_key(settings), token, expire: :timer.seconds(ttl(body)))
        {:ok, token}

      {:ok, body} ->
        {:error, {:yandex_eda, body}}

      error ->
        error
    end
  end

  defp ttl(%{"expires_in" => seconds}) when is_integer(seconds) and seconds > @token_margin,
    do: seconds - @token_margin

  defp ttl(_body), do: @token_margin

  defp cache_key(settings), do: {:yandex_eda_token, settings.push_client_id}
end
