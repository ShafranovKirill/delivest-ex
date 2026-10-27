defmodule Delivest.Integrations.Frontpad do
  @behaviour Delivest.Integrations.Crm.Provider

  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Frontpad.{Api, OrderPayload, Webhook}
  alias Delivest.Net

  @permanent_errors ~w(invalid_secret api_off invalid_plant invalid_product_keys invalid_certificate)
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

  def webhook_url(token), do: Crm.webhook_url(key(), token)

  @impl true
  def handle_webhook(token, params), do: Webhook.handle(token, params)

  @impl true
  def deliver_order(order, settings) do
    products = Net.list_products_by_ids(Enum.map(order.items, & &1.product_id))

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
  def rate_limit(%{api_key: api_key}), do: {{:frontpad, api_key}, request_interval_ms()}

  @impl true
  def classify_error(:missing_api_key), do: :permanent
  def classify_error({:missing_external_id, _product_id}), do: :permanent
  def classify_error({:frontpad, error}) when error in @permanent_errors, do: :permanent

  def classify_error({:frontpad, error}) when is_map_key(@snooze, error),
    do: {:snooze, @snooze[error]}

  def classify_error(_reason), do: :retry

  defp request_interval_ms,
    do:
      :delivest |> Application.get_env(__MODULE__, []) |> Keyword.get(:request_interval_ms, 2_000)
end
