defmodule Delivest.Push.StaffWorker do
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 30, keys: [:event, :id], states: [:available, :scheduled]]

  alias Delivest.Push.StaffDispatch

  @events ~w(order_created order_ready channel_cancelled delivery_requested delivery_assigned)

  def events, do: @events

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event" => event, "id" => id}}) when event in @events,
    do: StaffDispatch.run(String.to_existing_atom(event), id)
end
