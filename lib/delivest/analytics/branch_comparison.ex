defmodule Delivest.Analytics.BranchComparison do
  @moduledoc "Presentation rows derived exclusively from authorized Reports branch buckets."

  def rows(branches, {from, to}, metric) when metric in ~w(revenue orders_per_day avg_check) do
    days = Date.diff(to, from) + 1

    branches
    |> Enum.map(fn branch ->
      value =
        case metric do
          "revenue" ->
            branch.counts["revenue"]

          "orders_per_day" ->
            branch.counts["completed"] / days

          "avg_check" ->
            if branch.counts["completed"] > 0,
              do: round(branch.counts["revenue"] / branch.counts["completed"]),
              else: nil
        end

      Map.merge(branch, %{value: value, calendar_days: days})
    end)
    |> Enum.sort_by(fn row ->
      {if(is_nil(row.value), do: 1, else: 0), -(row.value || 0), row.name, row.branch_id}
    end)
  end
end
