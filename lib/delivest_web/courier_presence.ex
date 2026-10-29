defmodule DelivestWeb.CourierPresence do
  use Phoenix.Presence, otp_app: :delivest, pubsub_server: Delivest.PubSub

  def track_courier(pid, branch_id, staff),
    do: track(pid, topic(branch_id), staff.id, %{since: DateTime.utc_now(), position: nil})

  def locate(pid, branch_id, staff, position) do
    update(pid, topic(branch_id), staff.id, fn meta ->
      %{meta | position: Map.put(position, :at, DateTime.utc_now())}
    end)
  end

  def subscribe(branch_id),
    do: Phoenix.PubSub.subscribe(Delivest.PubSub, status_topic(branch_id))

  def online(branch_id) do
    branch_id
    |> topic()
    |> list()
    |> Map.new(fn {staff_id, %{metas: metas}} -> {staff_id, latest(metas)} end)
  end

  def positions(branch_id, couriers) do
    online = online(branch_id)

    for courier <- couriers,
        %{position: %{} = position} <- [online[courier.id]],
        do: %{
          id: courier.id,
          name: courier.name || courier.login,
          lat: position.lat,
          lng: position.lng,
          at: position.at
        }
  end

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_metas("couriers_online:" <> branch_id, _diff, _presences, state) do
    Phoenix.PubSub.local_broadcast(
      Delivest.PubSub,
      status_topic(branch_id),
      {:courier_presence, branch_id}
    )

    {:ok, state}
  end

  defp latest(metas) do
    metas
    |> Enum.filter(& &1.position)
    |> Enum.max_by(& &1.position.at, DateTime, fn -> hd(metas) end)
  end

  defp topic(branch_id), do: "couriers_online:#{branch_id}"

  defp status_topic(branch_id), do: "courier_presence:#{branch_id}"
end
