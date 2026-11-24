defmodule Delivest.Oms.OrderAttention do
  @moduledoc "Shared predicate and daily count for orders needing attention."

  import Ecto.Query

  alias Delivest.Oms.{OrderDeadline, Orders}

  @active_statuses [:created, :accepted, :preparing, :ready, :delivering]

  def expression(branch_id) do
    delivery_minutes = OrderDeadline.delivery_minutes(branch_id)

    crm_problem =
      dynamic(
        [o],
        fragment(
          "coalesce(?->>'alert', '') <> '' OR ?->>'status' IN ('failed', 'unknown')",
          o.crm,
          o.crm
        )
      )

    dynamic(^crm_problem or ^OrderDeadline.overdue_expr(delivery_minutes))
  end

  def count_for_day(branch_id, %Date{} = day) do
    %{branch_id: branch_id, date_from: day, date_to: day, problem: true}
    |> Orders.count_by_status()
    |> Map.take(@active_statuses)
    |> Map.values()
    |> Enum.sum()
  end
end
