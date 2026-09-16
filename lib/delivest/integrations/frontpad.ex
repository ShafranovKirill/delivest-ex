defmodule Delivest.Integrations.Frontpad do
  alias Delivest.Oms.Orders
  alias Delivest.Identity.Branch

  @spec enabled?(Branch.t() | nil) :: boolean()
  def enabled?(%Branch{info: %{frontpad_enabled: true}}), do: true
  def enabled?(_), do: false

  @spec api_key(Branch.t() | nil) :: String.t() | nil
  def api_key(%Branch{info: %{frontpad_api_key: api_key}}) when not is_nil(api_key), do: api_key
  def api_key(_), do: nil

  @spec settings(Branch.t() | nil) :: map() | nil
  def settings(%Branch{info: %{frontpad_settings: settings}}) do
    case settings do
      %{frontpad_branch_id: fb_id} when not is_nil(fb_id) -> %{frontpad_branch_id: fb_id}
      _ -> nil
    end
  end

  def settings(_), do: nil

  def create_order(attrs, _branch) do
    enriched_attrs =
      attrs
      |> Map.put("status", "completed")

    case Orders.create_order(enriched_attrs) do
      {:ok, _order} = result ->
        result

      {:error, _step, _reason} = error ->
        error
    end
  end
end
