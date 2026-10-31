defmodule Delivest.Integrations.Crm.StopPoller do
  @behaviour Delivest.Integrations.Poller

  alias Delivest.Integrations.Crm.{Lookup, StopSync}

  @impl true
  def key, do: :crm_stops

  @impl true
  def interval, do: 600

  @impl true
  def targets, do: Lookup.crm_branch_ids()

  @impl true
  def poll(branch_id), do: StopSync.sync(branch_id)
end
