defmodule Delivest.Push.NoteWorker do
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 60, keys: [:order_id, :note], states: [:available, :scheduled]]

  import Ecto.Query

  alias Delivest.Oms.Order
  alias Delivest.Push.{OrderMessage, Sender, Subscription}
  alias Delivest.Repo

  @notes ~w(card_only)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id, "note" => note}}) when note in @notes do
    case Repo.get(Order, order_id) do
      %Order{} = order ->
        Subscription
        |> where([s], s.order_id == ^order_id)
        |> Repo.all()
        |> Enum.map(&deliver(&1, order, note))
        |> Enum.find(:ok, &match?({:error, _reason}, &1))

      nil ->
        :ok
    end
  end

  defp deliver(subscription, order, note) do
    message = OrderMessage.note(order, String.to_existing_atom(note), subscription.locale)

    case Sender.deliver(subscription, message) do
      :expired ->
        Repo.delete!(subscription)
        :ok

      result ->
        result
    end
  end
end
