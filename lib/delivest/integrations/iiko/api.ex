defmodule Delivest.Integrations.Iiko.Api do
  alias Delivest.HTTP.Client
  alias Delivest.Integrations.TokenCache

  @host "https://api-ru.iiko.services"
  @token_ttl 3_600
  @timeout_seconds 15

  def token(api_key) do
    {path, body} =
      case app() do
        %{app_id: app_id, client_secret: secret} when is_binary(app_id) and is_binary(secret) ->
          {"/api/v2/access_token", %{appId: app_id, clientSecret: secret, apiKey: api_key}}

        _legacy ->
          {"/api/1/access_token", %{apiLogin: api_key}}
      end

    case Client.post(path, body, options(nil)) do
      {:ok, %{"token" => token}} when is_binary(token) -> {:ok, token, @token_ttl}
      {:ok, body} -> {:error, {:iiko, error_text(body)}}
      error -> normalize(error)
    end
  end

  def organizations(settings),
    do: call(settings, "/api/1/organizations", %{returnAdditionalInfo: false})

  def terminal_groups(settings),
    do: call(settings, "/api/1/terminal_groups", %{organizationIds: [settings.organization_id]})

  def alive(settings) do
    call(settings, "/api/1/terminal_groups/is_alive", %{
      organizationIds: [settings.organization_id],
      terminalGroupIds: [settings.terminal_group_id]
    })
  end

  def payment_types(settings),
    do: call(settings, "/api/1/payment_types", %{organizationIds: [settings.organization_id]})

  def create_delivery(settings, order) do
    call(settings, "/api/1/deliveries/create", %{
      organizationId: settings.organization_id,
      terminalGroupId: settings.terminal_group_id,
      order: order
    })
  end

  def deliveries(settings, ids) do
    call(settings, "/api/1/deliveries/by_id", %{
      organizationId: settings.organization_id,
      orderIds: ids
    })
  end

  def command_status(settings, correlation_id) do
    call(settings, "/api/1/commands/status", %{
      organizationId: settings.organization_id,
      correlationId: correlation_id
    })
  end

  def cancel(settings, order_id),
    do: order_command(settings, "/api/1/deliveries/cancel", order_id, %{})

  def change_comment(settings, order_id, comment),
    do: order_command(settings, "/api/1/deliveries/change_comment", order_id, %{comment: comment})

  def change_complete_before(settings, order_id, complete_before) do
    order_command(settings, "/api/1/deliveries/change_complete_before", order_id, %{
      newCompleteBefore: complete_before
    })
  end

  def stop_lists(settings) do
    call(settings, "/api/1/stop_lists", %{
      organizationIds: [settings.organization_id],
      terminalGroupsIds: [settings.terminal_group_id]
    })
  end

  def nomenclature(settings),
    do: call(settings, "/api/1/nomenclature", %{organizationId: settings.organization_id})

  def update_webhooks(settings, url) do
    call(settings, "/api/1/webhooks/update_settings", %{
      organizationId: settings.organization_id,
      webHooksUri: url,
      authToken: settings.webhook_token,
      webHooksFilter: %{
        deliveryOrderFilter: %{
          orderStatuses: [
            "Unconfirmed",
            "WaitCooking",
            "ReadyForCooking",
            "CookingStarted",
            "CookingCompleted",
            "Waiting",
            "OnWay",
            "Delivered",
            "Closed",
            "Cancelled"
          ],
          errors: true
        },
        stopListUpdateFilter: %{updates: true}
      }
    })
  end

  defp order_command(settings, path, order_id, extra) do
    call(
      settings,
      path,
      Map.merge(%{organizationId: settings.organization_id, orderId: order_id}, extra)
    )
  end

  defp call(settings, path, body) do
    TokenCache.run(
      {:iiko, settings.api_key},
      fn -> token(settings.api_key) end,
      &(path |> Client.post(body, options(&1)) |> normalize())
    )
  end

  defp options(token) do
    auth = if token, do: [{"authorization", "Bearer " <> token}], else: []

    [
      base_url: host(),
      journal: :iiko,
      timeout: (@timeout_seconds + 5) * 1_000,
      headers: [{"timeout", to_string(@timeout_seconds)} | auth]
    ]
  end

  defp normalize({:ok, %{} = body}), do: {:ok, body}
  defp normalize({:ok, body}), do: {:error, {:iiko, inspect(body)}}

  defp normalize({:error, {:http_error, status, body}}) when status in [400, 404, 409, 500],
    do: {:error, {:iiko, status, error_text(body)}}

  defp normalize(error), do: error

  defp error_text(%{"errorDescription" => text}) when is_binary(text), do: text
  defp error_text(%{"description" => text}) when is_binary(text), do: text
  defp error_text(body), do: inspect(body)

  defp host, do: Keyword.get(config(), :host, @host)

  defp app, do: Map.new(Keyword.take(config(), [:app_id, :client_secret]))

  defp config, do: Application.get_env(:delivest, Delivest.Integrations.Iiko, [])
end
