defmodule Delivest.Fiscal.OrderSubscriber do
  @behaviour Delivest.Events.Subscriber

  import Ecto.Query

  alias Delivest.Fiscal
  alias Delivest.Fiscal.{BranchSettings, Receipt}
  alias Delivest.Identity.Staff
  alias Delivest.Oms.Order
  alias Delivest.Payments.Payment
  alias Delivest.Repo

  @impl true
  def key, do: :fiscal

  @impl true
  def events, do: ["order.status_changed"]

  @impl true
  def handle(%{payload: %{"to" => "completed"} = payload} = event) do
    with false <- Map.get(payload, "reverted", false),
         %Order{deleted_at: nil, channel: nil, crm: nil} = order <-
           Repo.get(Order, event.aggregate_id),
         %BranchSettings{mode: :own} = settings <- Fiscal.settings(order.branch_id) do
      cashier = cashier(event.actor)

      order
      |> payments(settings)
      |> Enum.reduce_while(:ok, fn payment, :ok ->
        case Fiscal.issue(order, [payment], cashier: cashier) do
          {:ok, _receipt} -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    else
      _skip -> :ok
    end
  end

  def handle(_event), do: :ok

  def payments(%Order{} = order, %BranchSettings{} = settings) do
    issued =
      from(r in Receipt,
        where: r.status != :fail and r.kind == :sell and not is_nil(r.payment_id),
        select: r.payment_id
      )

    from(p in Payment,
      where: p.order_id == ^order.id and p.status == :paid and p.method in [:cash, :card],
      where: is_nil(p.fiscalized_by) and (is_nil(p.provider) or p.provider != "yandex_delivery"),
      where: p.id not in subquery(issued)
    )
    |> Repo.all()
    |> Enum.reject(&terminal?(&1, order, settings))
  end

  defp terminal?(%Payment{method: :card}, %Order{fulfillment_type: :delivery}, %{
         courier_card: :terminal
       }),
       do: true

  defp terminal?(_payment, _order, _settings), do: false

  defp cashier(%{"kind" => kind, "id" => id}) when kind in ["staff", "courier"] do
    case Repo.get(Staff, id) do
      %Staff{name: name} -> name
      _ -> nil
    end
  end

  defp cashier(_actor), do: nil
end
