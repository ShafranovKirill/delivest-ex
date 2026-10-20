defmodule Delivest.Integrations.Frontpad do
  @behaviour Delivest.Integrations.Crm.Provider

  alias Delivest.Integrations.Frontpad.{Api, FrontpadView}
  alias Delivest.Net

  @permanent_errors ~w(invalid_secret api_off invalid_plant invalid_product_keys invalid_certificate)
  @snooze %{"requests_limit" => 60, "cash_close" => 600}

  @impl true
  def name, do: "Frontpad"

  @impl true
  def deliver_order(order, settings) do
    products = Net.list_products_by_ids(Enum.map(order.items, & &1.product_id))

    with {:ok, view} <- FrontpadView.build(order, settings, products) do
      view |> FrontpadView.to_form_params() |> Api.new_order()
    end
  end

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
