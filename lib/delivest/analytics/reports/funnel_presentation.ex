defmodule Delivest.Analytics.Reports.FunnelPresentation do
  @moduledoc "Aggregates only versioned ordered funnel buckets; never mixes legacy stages."

  alias Delivest.Analytics.Reports.OrderedFunnel
  alias Delivest.Analytics.Reports.Query

  @keys ~w(session_started menu_view cart_add checkout_start order_created)

  def apply(data, ids, from, to, visibility) do
    %{legacy_days: legacy_days, rows: counts} =
      Query.funnel_aggregate(ids, from, to, visibility)

    stages =
      Map.new(counts, fn [dimension, key, sessions | _] -> {{dimension, key}, sessions} end)

    started = Map.get(stages, {"stage", "session_started"}, 0)

    stage_rows =
      @keys
      |> Enum.with_index()
      |> Enum.map(fn {key, index} ->
        sessions = Map.get(stages, {"stage", key}, 0)

        previous =
          if index == 0, do: nil, else: Map.get(stages, {"stage", Enum.at(@keys, index - 1)}, 0)

        next =
          if index == 4, do: nil, else: Map.get(stages, {"stage", Enum.at(@keys, index + 1)}, 0)

        %{
          family: "funnel",
          dimension: "stage",
          key: key,
          counts: %{
            "algorithm_version" => OrderedFunnel.version(),
            "sessions" => sessions,
            "from_previous_percent" => percent(sessions, previous),
            "from_start_percent" => percent(sessions, started),
            "lost_to_next" => if(next == nil, do: nil, else: sessions - next)
          }
        }
      end)

    [
      _,
      _,
      _,
      product,
      quick,
      without_cart,
      out_of_order,
      linked_without_checkout,
      linked_before_checkout
    ] =
      Enum.find(counts, ["coverage", "paths", 0, 0, 0, 0, 0, 0, 0], fn [dimension, key | _] ->
        dimension == "coverage" and key == "paths"
      end)

    coverage_row = %{
      family: "funnel",
      dimension: "coverage",
      key: "paths",
      counts: %{
        "algorithm_version" => OrderedFunnel.version(),
        "direct_product_entry" => product,
        "quick_add_entry" => quick,
        "checkout_without_cart_event" => without_cart,
        "checkout_out_of_order" => out_of_order,
        "linked_order_without_checkout" => linked_without_checkout,
        "linked_order_before_checkout" => linked_before_checkout,
        "legacy_snapshot_days" => legacy_days
      }
    }

    other_rows =
      Enum.reject(data.rows, fn row ->
        row.dimension in ["stage", "coverage"] or
          (legacy_days > 0 and row.dimension == "order")
      end)

    %{
      data
      | rows: stage_rows ++ [coverage_row] ++ other_rows,
        total_rows: length(stage_rows) + 1 + length(other_rows),
        totals: Map.put(data.totals, "sessions", started)
    }
    |> Map.put(:legacy_days, legacy_days)
  end

  defp percent(_, nil), do: nil
  defp percent(_, 0), do: nil
  defp percent(value, denominator), do: Float.round(value * 100 / denominator, 2)
end
