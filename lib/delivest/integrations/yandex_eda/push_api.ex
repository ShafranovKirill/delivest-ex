defmodule Delivest.Integrations.YandexEda.PushApi do
  alias Delivest.HTTP.Client
  alias Delivest.Integrations.TokenCache
  alias Delivest.Integrations.YandexEda.Settings

  @base_url "https://dc-partner.eda.yandex.net"
  @default_ttl 60

  def reload_menu(%Settings{} = settings, restaurant_id, operation),
    do:
      call(settings, "/menu/import/initiation", %{
        restaurantId: restaurant_id,
        operationType: operation
      })

  def block(%Settings{} = settings, vendors, attrs),
    do: call(settings, "/block", Map.put(attrs, :vendorInfo, vendors))

  def unblock(%Settings{} = settings, vendors, block_ids),
    do: call(settings, "/unblock", %{vendorInfo: vendors, blockIds: block_ids})

  def blocks(%Settings{} = settings, vendors) do
    with {:ok, %{"items" => items}} <-
           call(settings, "/v2/status", %{vendorInfo: vendors, statuses: ["enabled"]}) do
      {:ok, items}
    else
      {:ok, body} -> {:error, {:yandex_eda, body}}
      error -> error
    end
  end

  def validate_code(%Settings{} = settings, order_id, code),
    do: call(settings, "/platform/orders/#{URI.encode(order_id)}/codes/validate", %{code: code})

  def orders_history(%Settings{} = settings, filter) do
    with {:ok, %{"orders" => orders}} <- call(settings, "/v1/orders-history", filter) do
      {:ok, orders}
    else
      {:ok, body} -> {:error, {:yandex_eda, body}}
      error -> error
    end
  end

  defp call(settings, path, body) do
    TokenCache.run(token_key(settings), fn -> issue(settings) end, fn token ->
      Client.post(path, body,
        base_url: @base_url,
        journal: :yandex_eda,
        headers: [{"authorization", "Bearer " <> token}, {"partner-name", settings.partner_name}]
      )
    end)
  end

  def configured?(%Settings{} = settings),
    do:
      Enum.all?(
        [settings.partner_name, settings.push_client_id, settings.push_client_secret],
        &(&1 not in [nil, ""])
      )

  defp issue(settings) do
    "/oauth2/token"
    |> Client.post(
      [client_id: settings.push_client_id, client_secret: settings.push_client_secret],
      base_url: @base_url,
      format: :form,
      journal: :yandex_eda
    )
    |> case do
      {:ok, %{"access_token" => token} = body} ->
        {:ok, token, ttl(body)}

      {:ok, body} ->
        {:error, {:yandex_eda, body}}

      error ->
        error
    end
  end

  defp ttl(%{"expires_in" => seconds}) when is_integer(seconds) and seconds > 0, do: seconds
  defp ttl(_body), do: @default_ttl

  defp token_key(settings), do: {:yandex_eda, settings.push_client_id}
end
