defmodule Delivest.Push.Dispatch do
  import Ecto.Query

  require Logger

  alias Delivest.Oms.{Order, OrderStatus}
  alias Delivest.Push.{OrderMessage, Sender, Subscription}
  alias Delivest.Repo

  def run(order_id) do
    case Repo.get(Order, order_id) do
      %Order{} = order -> notify_all(order, OrderStatus.current(order))
      nil -> :ok
    end
  end

  defp notify_all(order, status) do
    results = order.id |> subscriptions() |> Enum.map(&notify(&1, order, status))

    if Enum.any?(results, &match?({:error, _reason}, &1)),
      do: {:error, :push_failed},
      else: finish(order.id, status)
  end

  defp notify(%Subscription{} = subscription, order, status) do
    if OrderMessage.notified?(status) and subscription.notified_status != to_string(status) do
      subscription
      |> Sender.deliver(OrderMessage.build(order, status, subscription.locale))
      |> settle(subscription, status)
    else
      :ok
    end
  end

  defp settle(:ok, subscription, status) do
    subscription |> Subscription.notified_changeset(status) |> Repo.update!()
    :ok
  end

  defp settle(:expired, subscription, _status) do
    Repo.delete!(subscription)
    :ok
  end

  defp settle({:error, reason} = error, subscription, _status) do
    Logger.warning("push to #{URI.parse(subscription.endpoint).host} failed: #{inspect(reason)}")
    error
  end

  defp finish(order_id, status) do
    if status in OrderStatus.final(), do: Repo.delete_all(subscriptions_query(order_id))
    :ok
  end

  defp subscriptions(order_id), do: order_id |> subscriptions_query() |> Repo.all()

  defp subscriptions_query(order_id), do: from(s in Subscription, where: s.order_id == ^order_id)
end
