defmodule Delivest.Loyalty.OrderSubscriber do
  @behaviour Delivest.Events.Subscriber

  alias Delivest.Loyalty
  alias Delivest.Oms.Order
  alias Delivest.Repo

  @impl true
  def key, do: :loyalty

  @impl true
  def events, do: ["order.status_changed"]

  @impl true
  def handle(event) do
    case Repo.get(Order, event.aggregate_id) do
      %Order{deleted_at: nil} = order -> run(event.payload, order)
      _order -> :ok
    end
  end

  defp run(%{"to" => "completed"}, order), do: wrap(Loyalty.accrue(order))
  defp run(%{"from" => "completed"}, order), do: wrap(Loyalty.reverse(order))
  defp run(%{"to" => "cancelled"}, order), do: wrap(Loyalty.reverse(order))
  defp run(_payload, _order), do: :ok

  defp wrap({:ok, _entry}), do: :ok
  defp wrap(error), do: error
end
