defmodule Delivest.Integrations.Crm.StopPoller do
  @behaviour Delivest.Integrations.Poller

  alias Delivest.Integrations.Crm.{Lookup, StopSync}
  alias Delivest.Integrations.Crm

  @impl true
  def key, do: :crm_stops

  @impl true
  def interval, do: 600

  @impl true
  def targets do
    Lookup.crm_branch_ids()
    |> Enum.reject(fn branch_id ->
      Crm.get_branch_settings(branch_id).provider == :frontpad
    end)
  end

  @impl true
  def poll(branch_id) do
    if Crm.get_branch_settings(branch_id).provider == :frontpad do
      :done
    else
      StopSync.sync(branch_id)
    end
  end
end
