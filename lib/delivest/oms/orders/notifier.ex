defmodule Delivest.Oms.Orders.Notifier do
  alias Delivest.Repo

  @source Delivest.Oms.Orders

  def subscribe(branch_id),
    do: Phoenix.PubSub.subscribe(Delivest.PubSub, events_topic(branch_id))

  def subscribe_branch(branch_id),
    do: Phoenix.PubSub.subscribe(Delivest.PubSub, branch_topic(branch_id))

  def subscribe_owner(kind, id) when kind in [:session, :client] and is_binary(id),
    do: Phoenix.PubSub.subscribe(Delivest.PubSub, owner_topic(kind, id))

  def subscribe_owner(_kind, _id), do: :ok

  def publish({:ok, order}, event) do
    order = Repo.preload(order, [:items, :client], force: true)

    Phoenix.PubSub.broadcast(
      Delivest.PubSub,
      events_topic(order.branch_id),
      {@source, event, order}
    )

    Phoenix.PubSub.broadcast(
      Delivest.PubSub,
      branch_topic(order.branch_id),
      {:branch_orders_changed, order.branch_id}
    )

    for {kind, id} <- [session: order.session_id, client: order.client_id],
        is_binary(id),
        do:
          Phoenix.PubSub.broadcast(Delivest.PubSub, owner_topic(kind, id), {:client_order, order})

    {:ok, order}
  end

  def publish(error, _event), do: error

  defp events_topic(branch_id), do: "orders:events:#{branch_id}"

  defp branch_topic(branch_id), do: "orders:branch:#{branch_id}"

  defp owner_topic(kind, id), do: "client_orders:#{kind}:#{id}"
end
