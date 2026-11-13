defmodule Delivest.Integrations.Crm.StopPoller do
  @behaviour Delivest.Integrations.Poller
  import Ecto.Query

  alias Delivest.Integrations.Availability
  alias Delivest.Integrations.Crm.{Lookup, StopSync}
  alias Delivest.Integrations.Crm
  alias Delivest.Net.ProductStop
  alias Delivest.Repo

  @impl true
  def key, do: :crm_stops

  @impl true
  def interval, do: 600

  @impl true
  def targets do
    (Lookup.crm_branch_ids() ++ stale_frontpad_branches())
    |> Enum.uniq()
    |> Enum.filter(fn branch_id ->
      settings = Crm.get_branch_settings(branch_id)

      if settings.provider == :frontpad do
        Availability.crm_allowed?(branch_id, :frontpad, :stops) or stale_frontpad?(branch_id)
      else
        Availability.crm_allowed?(branch_id, settings.provider, :stops)
      end
    end)
  end

  @impl true
  def poll(branch_id), do: poll(branch_id, Crm.get_branch_settings(branch_id).generation)

  def poll(branch_id, generation) do
    if branch_id in targets() do
      settings = Crm.get_branch_settings(branch_id)

      cond do
        settings.generation != generation ->
          :done

        settings.provider == :frontpad ->
          if Availability.crm_allowed?(branch_id, :frontpad, :stops, generation) do
            StopSync.sync_generation(branch_id, generation)
          else
            case StopSync.clear_frontpad(branch_id) do
              :ok -> :done
              error -> error
            end
          end

        true ->
          StopSync.sync_generation(branch_id, generation)
      end
    else
      :done
    end
  end

  defp stale_frontpad_branches do
    Repo.all(
      from(s in ProductStop, where: s.source == "frontpad", distinct: true, select: s.branch_id)
    )
  end

  defp stale_frontpad?(branch_id), do: branch_id in stale_frontpad_branches()
end
