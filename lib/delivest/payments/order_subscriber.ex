defmodule Delivest.Payments.OrderSubscriber do
  @behaviour Delivest.Events.Subscriber

  import Ecto.Query

  alias Delivest.Oms.Order
  alias Delivest.Payments.{Online, Payment}
  alias Delivest.Repo

  @taken [:accepted, :preparing, :ready, :delivering, :completed]

  @impl true
  def key, do: :payments

  @impl true
  def events, do: ["order.status_changed"]

  @impl true
  def handle(event) do
    case Repo.get(Order, event.aggregate_id) do
      %Order{deleted_at: nil} = order -> order |> payments() |> run(order)
      _order -> :ok
    end
  end

  defp payments(order) do
    Repo.all(
      from(p in Payment,
        where: p.order_id == ^order.id and p.provider == "yookassa" and not is_nil(p.external_id)
      )
    )
  end

  defp run(payments, order) do
    Enum.reduce_while(payments, :ok, fn payment, :ok ->
      case step(order, payment) do
        :ok -> {:cont, :ok}
        {:ok, _value} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp step(%Order{status: status} = order, %Payment{status: :authorized} = payment)
       when status in @taken,
       do: Online.capture(order, payment)

  defp step(%Order{status: :cancelled}, %Payment{status: :cancelled} = payment),
    do: Online.release(payment)

  defp step(_order, _payment), do: :ok
end
