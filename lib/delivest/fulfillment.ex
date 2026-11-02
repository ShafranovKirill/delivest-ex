defmodule Delivest.Fulfillment do
  alias Delivest.Identity
  alias Delivest.Identity.Branch.FulfillmentSettings

  def enabled(branch_id) do
    case Identity.get_branch(branch_id, preload: :info) do
      {:ok, %{info: %{fulfillment: settings}}} -> FulfillmentSettings.enabled(settings)
      _ -> FulfillmentSettings.enabled()
    end
  end

  def check(branch_id, type) do
    if to_string(type) in Enum.map(enabled(branch_id), &to_string/1),
      do: :ok,
      else: {:error, :fulfillment_unavailable}
  end
end
