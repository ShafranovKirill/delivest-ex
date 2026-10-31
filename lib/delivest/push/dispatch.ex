defmodule Delivest.Push.Dispatch do
  import Ecto.Query

  require Logger

  alias Delivest.Couriers
  alias Delivest.Oms.{Order, OrderFlow}
  alias Delivest.Push.{OrderMessage, Sender, Subscription}
  alias Delivest.Repo

  @before_pickup [:accepted, :preparing, :ready]

  def run(order_id) do
    case Repo.get(Order, order_id) do
      %Order{} = order -> order |> Repo.preload(deliveries: :courier) |> notify_all()
      nil -> :ok
    end
  end

  defp notify_all(order) do
    contact = Couriers.contact(order)
    results = order.id |> subscriptions() |> Enum.map(&notify(&1, order, contact))

    if Enum.any?(results, &match?({:error, _reason}, &1)),
      do: {:error, :push_failed},
      else: finish(order.id, order.status)
  end

  defp notify(%Subscription{} = subscription, order, contact) do
    subscription
    |> messages(order, contact)
    |> deliver(subscription)
    |> settle(subscription, order.status, contact)
  end

  defp messages(subscription, order, contact) do
    [
      status_due?(subscription, order.status) &&
        OrderMessage.build(order, order.status, contact, subscription.locale),
      courier_due?(subscription, order.status, contact) &&
        OrderMessage.courier(order, contact, subscription.locale)
    ]
    |> Enum.filter(& &1)
  end

  defp status_due?(subscription, status),
    do: OrderMessage.notified?(status) and subscription.notified_status != to_string(status)

  defp courier_due?(_subscription, _status, nil), do: false

  defp courier_due?(subscription, status, contact),
    do: status in @before_pickup and subscription.notified_courier != contact.name

  defp deliver([], _subscription), do: :skip

  defp deliver(messages, subscription) do
    Enum.reduce_while(messages, :ok, fn message, :ok ->
      case Sender.deliver(subscription, message) do
        :ok -> {:cont, :ok}
        other -> {:halt, other}
      end
    end)
  end

  defp settle(:skip, _subscription, _status, _contact), do: :ok

  defp settle(:ok, subscription, status, contact) do
    subscription
    |> Subscription.notified_changeset(status, contact && contact.name)
    |> Repo.update!()

    :ok
  end

  defp settle(:expired, subscription, _status, _contact) do
    Repo.delete!(subscription)
    :ok
  end

  defp settle({:error, reason} = error, subscription, _status, _contact) do
    Logger.warning("push to #{URI.parse(subscription.endpoint).host} failed: #{inspect(reason)}")
    error
  end

  defp finish(order_id, status) do
    if status in OrderFlow.final(), do: Repo.delete_all(subscriptions_query(order_id))
    :ok
  end

  defp subscriptions(order_id), do: order_id |> subscriptions_query() |> Repo.all()

  defp subscriptions_query(order_id), do: from(s in Subscription, where: s.order_id == ^order_id)
end
