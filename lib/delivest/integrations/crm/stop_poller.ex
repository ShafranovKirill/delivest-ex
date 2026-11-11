defmodule Delivest.Integrations.Crm.StopPoller do
  @behaviour Delivest.Integrations.Poller

  alias Delivest.Integrations.Crm.{Lookup, StopSync}
  alias Delivest.Integrations.Frontpad
  alias Delivest.Integrations.Crm

  @impl true
  def key, do: :crm_stops

  @impl true
  def interval, do: 600

  @impl true
  def targets do
    Lookup.crm_branch_ids()
    |> Enum.reject(fn branch_id ->
      settings = Crm.get_branch_settings(branch_id)
      settings.provider == :frontpad and Frontpad.stops_enabled?(settings.frontpad)
    end)
  end

  @impl true
  def poll(branch_id) do
    settings = Crm.get_branch_settings(branch_id)

    case settings.provider do
      :frontpad ->
        if Frontpad.stops_enabled?(settings.frontpad) do
          :done
        else
          case StopSync.clear_frontpad(branch_id) do
            :ok -> :done
            error -> error
          end
        end

      _ ->
        StopSync.sync(branch_id)
    end
  end
end
