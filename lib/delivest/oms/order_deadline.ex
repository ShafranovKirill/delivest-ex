defmodule Delivest.Oms.OrderDeadline do
  import Ecto.Query

  alias Delivest.{Identity, LocalTime}
  alias Delivest.Oms.{Order, OrderScopes}

  @default_delivery_minutes 60
  @min_kitchen_minutes 20

  def delivery_minutes(branch_id) do
    case Identity.get_branch(branch_id, preload: :info) do
      {:ok, %{info: %{delivery_time: minutes}}} when is_integer(minutes) and minutes > 0 ->
        minutes

      _ ->
        @default_delivery_minutes
    end
  end

  def lead_minutes(:delivery, delivery_minutes), do: delivery_minutes

  def lead_minutes(_type, delivery_minutes),
    do: max(@min_kitchen_minutes, round(delivery_minutes / 2))

  def at(%Order{cook_by: %NaiveDateTime{} = cook_by}, _delivery_minutes),
    do: LocalTime.naive_to_utc(cook_by)

  def at(%Order{} = order, delivery_minutes),
    do:
      DateTime.add(
        order.inserted_at,
        lead_minutes(order.fulfillment_type, delivery_minutes),
        :minute
      )

  def by_urgency(query, delivery_minutes) do
    status = OrderScopes.effective_status()
    finished = dynamic(fragment("? IN ('completed', 'cancelled')", ^status))
    unconfirmed = dynamic(fragment("? = 'created'", ^status))

    deadline =
      dynamic(
        [o],
        fragment(
          "coalesce(timezone(?, ?), timezone('UTC', ?) + make_interval(mins => CASE WHEN ? = 'delivery' THEN ?::integer ELSE ?::integer END))",
          ^LocalTime.timezone(),
          o.cook_by,
          o.inserted_at,
          o.fulfillment_type,
          ^lead_minutes(:delivery, delivery_minutes),
          ^lead_minutes(:pickup, delivery_minutes)
        )
      )

    rank =
      dynamic(
        [o],
        fragment(
          "CASE WHEN ? THEN -extract(epoch from ?) ELSE extract(epoch from ?) END",
          ^finished,
          o.inserted_at,
          ^deadline
        )
      )

    order_by(query, ^[asc: finished, desc: unconfirmed, asc: rank])
  end
end
