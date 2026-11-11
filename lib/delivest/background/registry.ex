defmodule Delivest.Background.Registry do
  @moduledoc "Allowlist of optional calculations; add consumers here when implemented."
  # The shared dispatcher can wake up five minutes after a due time, and an
  # analytics run has a two-minute budget. Schedule before the 15m/24h stale
  # thresholds so a normal run can finish inside those targets.
  @analytics_dispatch_budget 300
  @analytics_run_budget 120
  @analytics_fast_interval 900 - @analytics_dispatch_budget - @analytics_run_budget
  @analytics_daily_interval 86_400 - @analytics_dispatch_budget - @analytics_run_budget

  @tasks %{
    "analytics.funnel" => %{
      manual?: true,
      feature: "analytics_funnel",
      handler: Delivest.Analytics.Reports.Refresh,
      interval: @analytics_fast_interval,
      scope: :branch,
      timeout: :timer.minutes(2),
      statement_timeout: :timer.seconds(20)
    },
    "analytics.links" => %{
      manual?: true,
      feature: "analytics_links",
      handler: Delivest.Analytics.Reports.Refresh,
      interval: @analytics_fast_interval,
      scope: :branch,
      timeout: :timer.minutes(2),
      statement_timeout: :timer.seconds(20)
    },
    "analytics.extended" => %{
      manual?: true,
      feature: "analytics_extended",
      handler: Delivest.Analytics.Reports.Refresh,
      interval: @analytics_daily_interval,
      scope: :branch,
      timeout: :timer.minutes(2),
      statement_timeout: :timer.seconds(20)
    },
    "marketing.preview" => %{
      manual?: true,
      feature: "marketing_policies",
      handler: Delivest.Marketing.Preview,
      interval: 86_400,
      scope: :franchise,
      timeout: :timer.minutes(2),
      statement_timeout: :timer.seconds(20)
    },
    "marketing.report" => %{
      manual?: true,
      feature: "marketing_policies",
      handler: Delivest.Marketing.Report,
      interval: 86_400,
      scope: :franchise,
      timeout: :timer.minutes(2),
      statement_timeout: :timer.seconds(20)
    },
    "notifications.dispatch" => %{
      feature: "notifications",
      handler: Delivest.Notifications.Dispatch,
      interval: 60,
      scope: :franchise,
      timeout: :timer.minutes(2),
      statement_timeout: :timer.seconds(20)
    },
    "marketing.evaluate" => %{
      manual?: true,
      feature: "marketing_policies",
      handler: Delivest.Marketing.Evaluate,
      interval: 86_400,
      scope: :franchise,
      timeout: :timer.minutes(2),
      statement_timeout: :timer.seconds(20)
    },
    "segments.refresh" => %{
      manual?: true,
      feature: "segments",
      handler: Delivest.Segments.Refresh,
      interval: 86_400,
      scope: :franchise,
      timeout: :timer.minutes(15),
      statement_timeout: :timer.seconds(30)
    }
  }

  def fetch(kind), do: Map.fetch(@tasks, kind)
  def all, do: @tasks

  def tasks_for_feature(feature),
    do: Enum.filter(@tasks, fn {_kind, task} -> task.feature == feature end)

  def feature_disabled(feature, scope) do
    Enum.each(tasks_for_feature(feature), fn {_kind, task} ->
      if Code.ensure_loaded?(task.handler) and function_exported?(task.handler, :on_disable, 1),
        do: task.handler.on_disable(scope)
    end)

    :ok
  end
end
