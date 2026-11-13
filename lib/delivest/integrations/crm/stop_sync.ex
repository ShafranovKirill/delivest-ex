defmodule Delivest.Integrations.Crm.StopSync do
  import Ecto.Query, only: [from: 2]

  alias Delivest.Identity
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Availability
  alias Delivest.Integrations.Crm.{BranchSettings, Registry}
  alias Delivest.Integrations.Journal
  alias Delivest.Net.{ProductCrmIds, Stops}
  alias Delivest.Repo

  @cache :crm_cache

  @doc "Trusted scheduled sync. Staff callers must use sync/2."
  def sync(branch_id) do
    do_sync(branch_id, Crm.get_branch_settings(branch_id).generation)
  end

  def sync_generation(branch_id, generation), do: do_sync(branch_id, generation)

  defp do_sync(branch_id, generation) do
    case branch_id |> Crm.get_branch_settings() |> source() do
      {:ok, provider, module, settings} ->
        Journal.scope([branch_id: branch_id], fn ->
          fetch(branch_id, provider, module, settings, generation)
        end)

      :none ->
        clear_if_disabled(branch_id, generation)
    end
  end

  def sync(staff, branch_id) do
    with :ok <- Identity.authorize(staff, "integrations.update", branch_id),
         do: sync(branch_id)
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

  @doc "Remove only Frontpad stops when its synchronization is switched off."
  def clear_frontpad(branch_id) do
    with {:ok, _changed?} <- Stops.replace_external(branch_id, :frontpad, []) do
      forget_frontpad(branch_id)
      :ok
    end
  end

  defp forget_frontpad(branch_id) do
    Cachex.del(@cache, {:stops, branch_id})
    :ok
  catch
    :exit, _reason -> :ok
  end

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

  defp fetch(branch_id, provider, module, settings, generation) do
    with {:ok, external_ids} <- module.fetch_stops(settings) do
      Repo.transaction(fn ->
        Repo.one(from(i in BranchInfo, where: i.branch_id == ^branch_id, lock: "FOR SHARE"))

        with :ok <- current_source(branch_id, provider, settings, generation) do
          index = ProductCrmIds.by_external_id(branch_id, provider)
          {linked, unlinked} = Enum.split_with(external_ids, &Map.has_key?(index, &1))

          {:ok, _changed?} =
            Stops.replace_external(branch_id, provider, Enum.map(linked, &index[&1]))

          remember(branch_id, %{
            provider: provider,
            stopped: length(linked),
            unlinked: unlinked,
            synced_at: DateTime.utc_now(:second)
          })
        else
          {:ok, :disabled} -> {:ok, :disabled}
          error -> Repo.rollback(error)
        end
      end)
      |> case do
        {:ok, result} -> result
        {:error, result} -> result
      end
    end
  end

  defp current_source(branch_id, :frontpad, settings, generation) do
    current = Crm.get_branch_settings(branch_id)

    cond do
      BranchSettings.active_provider(current) != :frontpad or
          not Delivest.Integrations.Frontpad.stops_enabled?(current.frontpad) ->
        with :ok <- clear_frontpad(branch_id), do: {:ok, :disabled}

      current.frontpad != settings or current.generation != generation ->
        {:error, :settings_changed}

      true ->
        :ok
    end
  end

  defp current_source(branch_id, provider, settings, generation) do
    current = Crm.get_branch_settings(branch_id)

    if current.generation == generation and
         BranchSettings.active_provider(current) == provider and
         Map.get(current, provider) == settings and
         Availability.crm_allowed?(branch_id, provider, :stops, generation),
       do: :ok,
       else: {:error, :settings_changed}
  end

  defp clear(branch_id) do
    Enum.each(Registry.keys(), &Stops.replace_external(branch_id, &1, []))
    Cachex.del(@cache, {:stops, branch_id})
    {:ok, :disabled}
  end

  defp clear_if_disabled(branch_id, generation) do
    Repo.transaction(fn ->
      Repo.one(from(i in BranchInfo, where: i.branch_id == ^branch_id, lock: "FOR SHARE"))
      current = Crm.get_branch_settings(branch_id)

      if current.generation == generation and source(current) == :none,
        do: clear(branch_id),
        else: Repo.rollback({:error, :settings_changed})
    end)
    |> case do
      {:ok, result} -> result
      {:error, result} -> result
    end
  end

  defp remember(branch_id, result) do
    Cachex.put(@cache, {:stops, branch_id}, result)
    {:ok, result}
  end
end
