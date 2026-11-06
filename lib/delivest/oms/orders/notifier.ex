defmodule Delivest.Oms.Orders.Notifier do
  import Ecto.Query

  alias Delivest.Oms.Order
  alias Delivest.Repo

  @source Delivest.Oms.Orders
  @buffer_key {__MODULE__, :pending_notifications}

  def with_commit_notifications(fun) when is_function(fun, 0) do
    case Process.get(@buffer_key) do
      nil ->
        Process.put(@buffer_key, [])

        try do
          result = fun.()
          pending = Process.delete(@buffer_key)

          if match?({:ok, _}, result), do: Enum.each(Enum.reverse(pending), &flush/1)
          result
        after
          Process.delete(@buffer_key)
        end

      pending ->
        try do
          result = fun.()
          if not match?({:ok, _}, result), do: Process.put(@buffer_key, pending)
          result
        rescue
          error ->
            Process.put(@buffer_key, pending)
            reraise error, __STACKTRACE__
        end
    end
  end

  def subscribe(branch_id),
    do: Phoenix.PubSub.subscribe(Delivest.PubSub, events_topic(branch_id))

  def unsubscribe(branch_id),
    do: Phoenix.PubSub.unsubscribe(Delivest.PubSub, events_topic(branch_id))

  def subscribe_branch(branch_id),
    do: Phoenix.PubSub.subscribe(Delivest.PubSub, branch_topic(branch_id))

  def subscribe_owner(kind, id) when kind in [:session, :client] and is_binary(id),
    do: Phoenix.PubSub.subscribe(Delivest.PubSub, owner_topic(kind, id))

  def subscribe_owner(_kind, _id), do: :ok

  def publish({:ok, order}, event) do
    notify({:order, order.id, event})
    {:ok, Repo.preload(order, [:client, items: :modifiers, deliveries: :courier], force: true)}
  end

  def publish(error, _event), do: error

  def courier_changed(order_id) do
    # Push enqueues an Oban job in the caller's transaction so it remains durable.
    case Repo.get(Order, order_id) do
      %Order{} = order ->
        notify({:courier, order_id})
        Delivest.Push.order_changed(order)

      nil ->
        :ok
    end
  end

  defp notify(notification) do
    case Process.get(@buffer_key) do
      nil -> flush(notification)
      pending -> Process.put(@buffer_key, [notification | pending])
    end

    :ok
  end

  defp flush({kind, order_id, event}) when kind == :order do
    with_current_order(order_id, fn order ->
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

      publish_client(order)
    end)
  end

  defp flush({:courier, order_id}) do
    with_current_order(order_id, &publish_client/1)
  end

  defp with_current_order(order_id, fun) do
    Repo.transaction(fn ->
      query = from(o in Order, where: o.id == ^order_id, lock: "FOR UPDATE")

      case Repo.one(query) do
        %Order{} = order ->
          order
          |> Repo.preload([:client, items: :modifiers, deliveries: :courier])
          |> fun.()

        nil ->
          :ok
      end
    end)
  end

  defp publish_client(order) do
    owners =
      [client: order.client_id] ++
        if(order.guest_session_access, do: [session: order.session_id], else: [])

    for {kind, id} <- owners,
        is_binary(id),
        do:
          Phoenix.PubSub.broadcast(Delivest.PubSub, owner_topic(kind, id), {:client_order, order})

    :ok
  end

  def branch_changed(branch_id),
    do:
      Phoenix.PubSub.broadcast(
        Delivest.PubSub,
        branch_topic(branch_id),
        {:branch_orders_changed, branch_id}
      )

  defp events_topic(branch_id), do: "orders:events:#{branch_id}"

  defp branch_topic(branch_id), do: "orders:branch:#{branch_id}"

  defp owner_topic(kind, id), do: "client_orders:#{kind}:#{id}"
end
