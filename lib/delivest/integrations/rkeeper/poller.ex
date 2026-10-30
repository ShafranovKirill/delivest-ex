defmodule Delivest.Integrations.Rkeeper.Poller do
  @behaviour Delivest.Integrations.Poller

  alias Delivest.Integrations.Rkeeper

  @impl true
  def key, do: :rkeeper

  @impl true
  def interval, do: 30

  @impl true
  def targets, do: Rkeeper.active_branches()

  @impl true
  def poll(branch_id), do: Rkeeper.poll(branch_id)
end
