defmodule Delivest.Oms.OrderEvents do
  alias Delivest.Events
  alias Delivest.Identity.{Client, Staff}
  alias Delivest.Oms.{Order, OrderFlow}

  @tracked [
    :client_id,
    :fulfillment_type,
    :payment_method,
    :total_amount,
    :subtotal_amount,
    :discount_amount,
    :delivery_amount,
    :cook_by,
    :comment,
    :address
  ]

  def created(repo, %Order{} = order, actor) do
    Events.record(
      repo,
      "order.created",
      order,
      %{status: order.status, source: order.source},
      actor(actor, order)
    )
  end

  def status_changed(_repo, _order, [], _by, _reason), do: {:ok, nil}

  def status_changed(repo, %Order{} = order, steps, by, reason) do
    {from, _} = List.first(steps)
    {_, to} = List.last(steps)
    actor = actor(by, order)

    payload =
      %{from: from, to: to, source: OrderFlow.source(by), reason: reason}
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    with {:ok, event} <- Events.record(repo, "order.status_changed", order, payload, actor) do
      if to == :cancelled,
        do: Events.record(repo, "order.cancelled", order, payload, actor),
        else: {:ok, event}
    end
  end

  def reverted(repo, %Order{} = order, from, to, %Staff{} = staff, reason) do
    payload =
      %{from: from, to: to, source: :staff, reverted: true, reason: reason}
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    Events.record(repo, "order.status_changed", order, payload, actor(staff, order))
  end

  def updated(repo, %Order{} = old, %Order{} = new, actor) do
    case changes(old, new) do
      changes when changes == %{} ->
        {:ok, nil}

      changes ->
        Events.record(repo, "order.updated", new, %{changes: changes}, actor(actor, new))
    end
  end

  def payment_changed(repo, %Order{} = order, payment, change, actor) do
    payload = %{
      payment_id: payment.id,
      change: to_string(change),
      method: payment.method,
      status: payment.status,
      amount: payment.amount
    }

    Events.record(repo, "order.payment_changed", order, payload, actor)
  end

  def deleted(repo, %Order{} = order, actor),
    do: Events.record(repo, "order.deleted", order, %{}, actor(actor, order))

  def actor({kind, %Staff{id: id}}, _order) when kind in [:staff, :courier],
    do: %{kind: kind, id: id}

  def actor(%Staff{id: id}, _order), do: %{kind: :staff, id: id}
  def actor(%Client{id: id}, _order), do: %{kind: :client, id: id}
  def actor(:crm, %Order{crm: %{provider: provider}}), do: %{kind: :crm, provider: provider}
  def actor(:channel, %Order{channel: %{provider: p}}), do: %{kind: :channel, provider: p}
  def actor(kind, _order) when kind in [:crm, :channel, :delivery], do: %{kind: kind}
  def actor(_actor, _order), do: %{kind: :system}

  defp changes(old, new) do
    @tracked
    |> Enum.map(&{&1, dump(Map.get(old, &1)), dump(Map.get(new, &1))})
    |> then(&[{:items, items(old), items(new)} | &1])
    |> Enum.reject(fn {_field, from, to} -> from == to or :unknown in [from, to] end)
    |> Map.new(fn {field, from, to} -> {field, %{from: from, to: to}} end)
  end

  defp items(%Order{items: items}) when is_list(items) do
    items
    |> Enum.map(&Map.take(&1, [:product_id, :title, :price, :quantity, :gift]))
    |> Enum.sort_by(&{&1.product_id, &1.title, &1.gift})
  end

  defp items(_order), do: :unknown

  defp dump(%{__struct__: module} = embed) when module not in [Date, DateTime, NaiveDateTime],
    do: Ecto.embedded_dump(embed, :json)

  defp dump(value), do: value
end
