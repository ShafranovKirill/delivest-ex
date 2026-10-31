defmodule Delivest.Integrations.Crm.CatalogPoller do
  @behaviour Delivest.Integrations.Poller

  alias Delivest.Integrations.{Crm, Health}
  alias Delivest.Integrations.Crm.{Catalog, Lookup}

  @provider :frontpad

  @impl true
  def key, do: :crm_catalog

  @impl true
  def interval, do: 86_400

  @impl true
  def targets do
    Enum.filter(Lookup.crm_branch_ids(), &(Crm.default_provider(&1) == @provider))
  end

  @impl true
  def poll(branch_id) do
    case Catalog.refresh(branch_id, @provider) do
      {:ok, snapshot} -> report(branch_id, Catalog.issues(branch_id, snapshot))
      {:error, {:too_early, _at}} -> :done
      {:error, _reason} = error -> error
    end
  end

  defp report(branch_id, []) do
    Health.clear_warning(@provider, branch_id)
    :done
  end

  defp report(branch_id, issues) do
    Health.warn(@provider, branch_id, "catalog_issues:#{length(issues)}")
    :done
  end
end
