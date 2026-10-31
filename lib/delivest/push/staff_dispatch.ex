defmodule Delivest.Push.StaffDispatch do
  import Ecto.Query

  require Logger

  alias Delivest.{Couriers, Identity, Repo}
  alias Delivest.Couriers.Delivery
  alias Delivest.Identity.{Role, Staff, StaffBranch}
  alias Delivest.Oms.Order
  alias Delivest.Push.{Sender, StaffMessage, StaffSubscription}

  @operator_events [:order_created, :order_ready, :channel_cancelled]

  def run(event, id) do
    with {:ok, order, staff_ids} <- target(event, id),
         {:ok, branch} <- Identity.get_branch(order.branch_id) do
      message = StaffMessage.build(event, order, branch)
      staff_ids |> subscriptions() |> Enum.map(&deliver(&1, message)) |> outcome()
    else
      :skip -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp target(event, order_id) when event in @operator_events do
    case Repo.get(Order, order_id) do
      %Order{} = order ->
        if due?(event, order), do: {:ok, order, operators(order.branch_id)}, else: :skip

      nil ->
        :skip
    end
  end

  defp target(:delivery_requested, delivery_id) do
    case delivery(delivery_id) do
      %Delivery{status: :searching, provider: :staff} = delivery ->
        {:ok, delivery.order, delivery.branch_id |> Couriers.list_couriers() |> Enum.map(& &1.id)}

      _other ->
        :skip
    end
  end

  defp target(:delivery_assigned, delivery_id) do
    case delivery(delivery_id) do
      %Delivery{status: :assigned, courier_id: courier_id} = delivery
      when is_binary(courier_id) ->
        {:ok, delivery.order, [courier_id]}

      _other ->
        :skip
    end
  end

  defp due?(:order_created, order), do: order.status == :created
  defp due?(:order_ready, order), do: order.status == :ready
  defp due?(:channel_cancelled, order), do: order.status == :cancelled

  defp delivery(id), do: Delivery |> Repo.get(id) |> Repo.preload(:order)

  defp operators(branch_id) do
    Staff
    |> join(:inner, [s], r in Role, on: r.id == s.role_id)
    |> join(:left, [s], sb in StaffBranch, on: sb.staff_id == s.id and sb.branch_id == ^branch_id)
    |> where([s], is_nil(s.deleted_at))
    |> where(
      [_s, r, sb],
      fragment("? @> ?::jsonb", r.permissions, ^["admin"]) or
        (fragment("? @> ?::jsonb", r.permissions, ^["orders.update"]) and not is_nil(sb.staff_id))
    )
    |> select([s], s.id)
    |> Repo.all()
  end

  defp subscriptions([]), do: []

  defp subscriptions(staff_ids),
    do: Repo.all(from(s in StaffSubscription, where: s.staff_id in ^staff_ids))

  defp deliver(subscription, message) do
    case Sender.deliver(subscription, message) do
      :ok ->
        :ok

      :expired ->
        Repo.delete!(subscription)
        :ok

      {:error, reason} = error ->
        Logger.warning(
          "staff push to #{URI.parse(subscription.endpoint).host} failed: #{inspect(reason)}"
        )

        error
    end
  end

  defp outcome(results) do
    if Enum.any?(results, &match?({:error, _reason}, &1)), do: {:error, :push_failed}, else: :ok
  end
end
