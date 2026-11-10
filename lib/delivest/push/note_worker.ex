defmodule Delivest.Push.NoteWorker do
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 3,
    unique: [period: 60, keys: [:order_id, :note, :titles], states: [:available, :scheduled]]

  import Ecto.Query

  alias Delivest.Oms.Order
  alias Delivest.Push.{OrderMessage, Subscription}
  alias Delivest.Repo

  @notes ~w(card_only items_removed)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id, "note" => note} = args})
      when note in @notes do
    case Repo.get(Order, order_id) do
      %Order{} = order -> send_to_subscriptions(order, message(order, note, args))
      nil -> :ok
    end
  end

  defp message(order, "items_removed", args),
    do: items_removed(order, Map.get(args, "titles", []))

  defp message(order, note, _args),
    do: fn locale -> OrderMessage.note(order, String.to_existing_atom(note), locale) end

  defp items_removed(_order, []), do: nil

  defp items_removed(order, titles),
    do: fn locale -> OrderMessage.items_removed(order, titles, locale) end

  defp send_to_subscriptions(_order, nil), do: :ok

  defp send_to_subscriptions(order, message) do
    Subscription
    |> where([s], s.order_id == ^order.id)
    |> Repo.all()
    |> Enum.map(&deliver(&1, message.(&1.locale)))
    |> Enum.find(:ok, &match?({:error, _reason}, &1))
  end

  defp deliver(subscription, message) do
    case Delivest.Notifications.deliver_push(subscription, message, :transactional) do
      :expired ->
        Repo.delete!(subscription)
        :ok

      result ->
        result
    end
  end
end
