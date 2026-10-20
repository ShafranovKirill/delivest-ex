defmodule Delivest.Integrations.Frontpad do
  @behaviour Delivest.Integrations.Crm.Provider

  alias Delivest.Integrations.Frontpad.{Api, FrontpadView}
  alias Delivest.Net

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
  def permanent_error?(:missing_api_key), do: true
  def permanent_error?({:missing_external_id, _product_id}), do: true
  def permanent_error?(_reason), do: false
end
