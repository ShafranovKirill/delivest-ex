defmodule Delivest.Integrations.Frontpad.FrontpadService do
  alias Delivest.Identity.Branch
  alias Delivest.Oms.Orders
  alias Delivest.Integrations.Frontpad.FrontpadWorker

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

  @spec create_order(map(), Branch.t(), keyword()) ::
          {:ok, Delivest.Oms.Order.t()} | {:error, atom(), term()}
  def create_order(attrs, %Branch{} = branch, opts \\ []) do
    enriched_attrs = Map.put(attrs, "status", "crm")

    # The job is inserted in the same transaction as the order: either both exist or neither.
    Orders.create_order(
      enriched_attrs,
      Keyword.put(opts, :after_insert, fn multi ->
        Oban.insert(multi, :frontpad_job, fn %{order: order} ->
          FrontpadWorker.new(%{"order_id" => order.id, "branch_id" => branch.id})
        end)
      end)
    )
  end
end
