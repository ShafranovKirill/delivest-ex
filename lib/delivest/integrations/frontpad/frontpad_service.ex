defmodule Delivest.Integrations.Frontpad.FrontpadService do
  require Logger

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

  @spec create_order(map(), Branch.t()) ::
          {:ok, Delivest.Oms.Order.t()} | {:error, atom(), term()}
  def create_order(attrs, %Branch{} = branch) do
    enriched_attrs = Map.put(attrs, "status", "crm")

    case Orders.create_order(enriched_attrs) do
      {:ok, order} = result ->
        enqueue_frontpad_job(order, branch)
        result

      {:error, _step, _reason} = error ->
        error
    end
  end

  @spec enqueue_frontpad_job(Delivest.Oms.Order.t(), Branch.t()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  defp enqueue_frontpad_job(order, branch) do
    %{
      "order_id" => order.id,
      "branch_id" => branch.id
    }
    |> FrontpadWorker.new()
    |> Oban.insert()
  end
end
