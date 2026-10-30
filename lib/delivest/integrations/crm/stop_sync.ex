defmodule Delivest.Integrations.Crm.StopSync do
  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.{BranchSettings, Registry}
  alias Delivest.Integrations.Journal
  alias Delivest.Net.{ProductCrmIds, Stops}

  @cache :crm_cache

  def sync(branch_id) do
    case branch_id |> Crm.get_branch_settings() |> source() do
      {:ok, provider, module, settings} ->
        Journal.scope([branch_id: branch_id], fn ->
          fetch(branch_id, provider, module, settings)
        end)

      :none ->
        clear(branch_id)
    end
  end

  def interval_ms(branch_id) do
    with {:ok, _provider, module, settings} <- branch_id |> Crm.get_branch_settings() |> source(),
         {_key, interval} <- module.rate_limit(settings) do
      interval
    else
      _ -> 0
    end
  end

  def last(branch_id), do: Cachex.get!(@cache, {:stops, branch_id})

  defp source(crm) do
    with provider when not is_nil(provider) <- BranchSettings.active_provider(crm),
         {:ok, module} <- Registry.fetch(provider),
         true <- function_exported?(module, :fetch_stops, 1),
         settings = Map.get(crm, provider),
         true <- module.stops_enabled?(settings) do
      {:ok, provider, module, settings}
    else
      _ -> :none
    end
  end

  defp fetch(branch_id, provider, module, settings) do
    with {:ok, external_ids} <- module.fetch_stops(settings) do
      index = ProductCrmIds.by_external_id(branch_id, provider)
      {linked, unlinked} = Enum.split_with(external_ids, &Map.has_key?(index, &1))
      {:ok, _changed?} = Stops.replace_external(branch_id, provider, Enum.map(linked, &index[&1]))

      remember(branch_id, %{
        provider: provider,
        stopped: length(linked),
        unlinked: unlinked,
        synced_at: DateTime.utc_now(:second)
      })
    end
  end

  defp clear(branch_id) do
    Enum.each(Registry.keys(), &Stops.replace_external(branch_id, &1, []))
    Cachex.del(@cache, {:stops, branch_id})
    {:ok, :disabled}
  end

  defp remember(branch_id, result) do
    Cachex.put(@cache, {:stops, branch_id}, result)
    {:ok, result}
  end
end
