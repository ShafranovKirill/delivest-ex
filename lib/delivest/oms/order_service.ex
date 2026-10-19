defmodule Delivest.Oms.OrderService do
  alias Delivest.Oms.Orders
  alias Delivest.Identity
  alias Delivest.Integrations.Frontpad.FrontpadService

  @doc "Options are passed to `Delivest.Oms.Orders.create_order/2`."
  def create_order(attrs, opts \\ []) do
    with {:ok, branch} <- fetch_branch(attrs) do
      if FrontpadService.enabled?(branch) do
        FrontpadService.create_order(attrs, branch, opts)
      else
        Orders.create_order(attrs, opts)
      end
    end
  end

  defp fetch_branch(attrs) do
    case extract_branch_id(attrs) do
      nil ->
        {:error, :branch_id_required}

      branch_id ->
        case Identity.get_branch(branch_id, preload: [:info]) do
          {:ok, %Identity.Branch{} = branch} -> {:ok, branch}
          _ -> {:error, :branch_not_found}
        end
    end
  end

  defp extract_branch_id(attrs) do
    Map.get(attrs, "branch_id") || Map.get(attrs, :branch_id)
  end
end
