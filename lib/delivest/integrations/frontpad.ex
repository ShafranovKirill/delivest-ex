defmodule Delivest.Integrations.Frontpad do
  @behaviour Delivest.Integrations.Crm.Provider

  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Frontpad.{Api, OrderPayload, Webhook}
  alias Delivest.Net.ProductCrmIds

  @auth_errors ~w(invalid_secret api_off)
  @permanent_errors ~w(invalid_plant invalid_product_keys invalid_certificate)
  @snooze %{"requests_limit" => 60, "cash_close" => 600}

  @impl true
  def key, do: :frontpad

  @impl true
  def name, do: "Frontpad"

  @impl true
  def settings_schema, do: Delivest.Integrations.Frontpad.Settings

  @impl true
  def configured?(%{api_key: api_key}), do: api_key not in [nil, ""]
  def configured?(_settings), do: false

  @impl true
  def idempotent?, do: false

  @impl true
  def capabilities, do: []

  @impl true
  def status_map(settings),
    do: Delivest.Integrations.Frontpad.StatusCodes.to_map(settings.statuses)

  def webhook_url(token), do: Crm.webhook_url(key(), token)

  @impl true
  def handle_webhook(token, params), do: Webhook.handle(token, params)

  defp modifier_articles(order) do
    order.items
    |> Enum.flat_map(&modifiers/1)
    |> Enum.map(& &1.modifier_id)
    |> Enum.reject(&is_nil/1)
    |> Delivest.Net.Modifiers.crm_ids(key())
    |> Map.new(fn {modifier_id, external_id} -> {modifier_id, %{external_id: external_id}} end)
  end

  defp modifiers(%{modifiers: modifiers}) when is_list(modifiers), do: modifiers
  defp modifiers(_item), do: []

  @impl true
  def deliver_order(order, settings) do
    products =
      order.items
      |> Enum.map(& &1.product_id)
      |> ProductCrmIds.by_product(key())
      |> Map.new(fn {product_id, external_id} -> {product_id, %{external_id: external_id}} end)
      |> Map.merge(modifier_articles(order))

    with {:ok, payload} <- OrderPayload.build(order, settings, products) do
      payload |> OrderPayload.to_form_params() |> Api.new_order()
    end
  end

  @impl true
  def catalog_source(%{api_key: api_key}), do: {:frontpad, api_key}

  @impl true
  def fetch_catalog(%{api_key: api_key} = settings) when is_binary(api_key) and api_key != "" do
    Crm.Throttle.run(rate_limit(settings), fn ->
      Api.get_products(api_key)
    end)
  end

  def fetch_catalog(_settings), do: {:error, :missing_api_key}

  @impl true
  def stops_enabled?(%{sync_stops: true} = settings), do: configured?(settings)
  def stops_enabled?(_settings), do: false

  @impl true
  def fetch_stops(%{api_key: api_key} = settings) do
    Crm.Throttle.run(rate_limit(settings), fn -> Api.get_stops(api_key) end)
  end

  @impl true
  def rate_limit(%{api_key: api_key}), do: {{:frontpad, api_key}, request_interval_ms()}

  @impl true
  def classify_error(:missing_api_key), do: :permanent
  def classify_error({:missing_external_id, _product_id}), do: :permanent
  def classify_error({:frontpad, error}) when error in @auth_errors, do: :auth
  def classify_error({:frontpad, error}) when error in @permanent_errors, do: :permanent

  def classify_error({:frontpad, error}) when is_map_key(@snooze, error),
    do: {:snooze, @snooze[error]}

  def classify_error(reason), do: Delivest.Integrations.Error.classify(reason)

  @impl true
  def health_check(settings) do
    if configured?(settings) do
      with {:ok, _stops} <-
             Crm.Throttle.run(rate_limit(settings), fn -> Api.get_stops(settings.api_key) end),
           do: :ok
    else
      {:error, :not_configured}
    end
  end

  defp request_interval_ms,
    do:
      :delivest |> Application.get_env(__MODULE__, []) |> Keyword.get(:request_interval_ms, 2_000)
end
