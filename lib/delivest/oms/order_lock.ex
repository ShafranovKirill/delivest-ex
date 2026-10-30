defmodule Delivest.Oms.OrderLock do
  alias Delivest.{Couriers, Payments}
  alias Delivest.Integrations.Crm
  alias Delivest.Oms.Order

  @changes [:items, :address, :time, :payment_method, :comment]
  @swappable [:cash, :card_offline]
  @capabilities %{
    items: :update_items,
    address: :update_address,
    time: :update_time,
    payment_method: :update_payments,
    comment: :update_comment
  }
  @fields %{
    "items" => :items,
    "address" => :address,
    "fulfillment_type" => :address,
    "cook_by" => :time,
    "payment_method" => :payment_method,
    "comment" => :comment
  }

  def changes, do: @changes

  def editable(%Order{} = order) do
    payments = Payments.list(order.id)

    case Enum.find(@changes, &(check(order, &1, payments) == :ok)) do
      nil -> check(order, :comment, payments)
      _change -> :ok
    end
  end

  def allowed(%Order{} = order) do
    payments = Payments.list(order.id)
    Enum.filter(@changes, &(check(order, &1, payments) == :ok))
  end

  def check(%Order{} = order, change), do: check(order, change, Payments.list(order.id))

  def check_changes(%Order{} = old, %Order{} = new, changed_fields) do
    payments = Payments.list(old.id)

    changed_fields
    |> Enum.map(&Map.get(@fields, to_string(&1)))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.find_value(:ok, fn change ->
      case check(old, payment_change(change, new), payments) do
        :ok -> nil
        error -> error
      end
    end)
  end

  def revert(%Order{} = order) do
    if Couriers.handed_over?(order),
      do: {:error, :handed_to_courier},
      else: revert_payments(order, Payments.list(order.id))
  end

  defp revert_payments(%Order{status: :completed}, payments) do
    if locked_payment?(payments), do: {:error, :paid}, else: :ok
  end

  defp revert_payments(%Order{status: :cancelled}, payments) do
    if refunded?(payments), do: {:error, :refunded}, else: :ok
  end

  defp revert_payments(_order, _payments), do: :ok

  defp payment_change(:payment_method, %Order{payment_method: to}), do: {:payment_method, to}
  defp payment_change(change, _order), do: change

  defp check(%Order{status: status}, _change, _payments) when status in [:completed, :cancelled],
    do: {:error, :order_finished}

  defp check(%Order{awaiting_payment: true}, change, _payments) when change != :comment,
    do: {:error, :awaiting_payment}

  defp check(%Order{channel: %{}}, change, _payments) when change != :comment,
    do: {:error, :channel_order}

  defp check(%Order{crm: %{}} = order, change, payments) do
    if Crm.can?(order, Map.fetch!(@capabilities, kind(change))),
      do: by_state(order, change, payments),
      else: {:error, :crm_order}
  end

  defp check(order, change, payments), do: by_state(order, change, payments)

  defp by_state(_order, :comment, _payments), do: :ok

  defp by_state(%Order{status: :delivering} = order, {:payment_method, to}, payments) do
    if order.payment_method in @swappable and to in @swappable,
      do: by_payments({:payment_method, to}, payments),
      else: {:error, :with_courier}
  end

  defp by_state(%Order{status: :delivering}, _change, _payments), do: {:error, :with_courier}
  defp by_state(%Order{status: :ready}, :time, _payments), do: {:error, :order_ready}
  defp by_state(_order, change, payments), do: by_payments(change, payments)

  defp by_payments(change, payments) when change == :payment_method or is_tuple(change) do
    if paid?(payments), do: {:error, :paid}, else: :ok
  end

  defp by_payments(_change, _payments), do: :ok

  defp kind({change, _value}), do: change
  defp kind(change), do: change

  defp paid?(payments),
    do: Enum.any?(payments, &(&1.status == :paid and &1.method != :aggregator))

  defp locked_payment?(payments) do
    Enum.any?(payments, fn payment ->
      payment.status == :paid and payment.method in [:cash, :card] and
        not Payments.reopenable?(payment)
    end)
  end

  defp refunded?(payments),
    do: Enum.any?(payments, fn p -> Enum.any?(p.refunds || [], &(&1.status == :succeeded)) end)
end
