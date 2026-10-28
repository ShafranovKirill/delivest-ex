defmodule DelivestWeb.KitchenPresence do
  use Phoenix.Presence, otp_app: :delivest, pubsub_server: Delivest.PubSub

  @table :kitchen_last_seen

  def track_screen(pid, branch_id, staff),
    do: track(pid, topic(branch_id), staff.id, %{since: DateTime.utc_now()})

  def subscribe(branch_id),
    do: Phoenix.PubSub.subscribe(Delivest.PubSub, status_topic(branch_id))

  def status(branch_id) do
    if list(topic(branch_id)) == %{},
      do: {:offline, last_seen(branch_id)},
      else: :online
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set])
    {:ok, %{}}
  end

  @impl true
  def handle_metas("kitchen_screens:" <> branch_id, %{leaves: leaves}, presences, state) do
    if presences == %{} and leaves != %{},
      do: :ets.insert(@table, {branch_id, DateTime.utc_now()})

    Phoenix.PubSub.local_broadcast(
      Delivest.PubSub,
      status_topic(branch_id),
      {:kitchen_presence, branch_id}
    )

    {:ok, state}
  end

  defp last_seen(branch_id) do
    case :ets.lookup(@table, branch_id) do
      [{^branch_id, at}] -> at
      [] -> nil
    end
  end

  defp topic(branch_id), do: "kitchen_screens:#{branch_id}"

  defp status_topic(branch_id), do: "kitchen_presence:#{branch_id}"
end
