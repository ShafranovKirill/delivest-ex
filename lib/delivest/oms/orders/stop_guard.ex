defmodule Delivest.Oms.Orders.StopGuard do
  alias Delivest.Net.Stops
  alias Delivest.Promo.Result

  def check(nil, _pricing), do: {:ok, :available}

  def check(branch_id, %Result{lines: lines}),
    do: Stops.ensure_available(branch_id, Enum.map(lines, & &1.product_id))
end
