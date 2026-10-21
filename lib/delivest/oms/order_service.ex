defmodule Delivest.Oms.OrderService do
  alias Delivest.Identity
  alias Delivest.Integrations.Crm
  alias Delivest.Oms.Orders

  def create_order(attrs, opts \\ []) do
    with {:ok, branch} <- fetch_branch(attrs) do
      case Crm.active_provider(branch) do
        nil -> Orders.create_order(attrs, opts)
        provider -> Crm.create_order(attrs, provider, opts)
      end
    end
  end

  defp fetch_branch(attrs) do
    case Map.get(attrs, "branch_id") || Map.get(attrs, :branch_id) do
      nil ->
        {:error, :branch_id_required}

      branch_id ->
        case Identity.get_branch(branch_id, preload: [:info]) do
          {:ok, %Identity.Branch{} = branch} -> {:ok, branch}
          _ -> {:error, :branch_not_found}
        end
    end
  end
end
