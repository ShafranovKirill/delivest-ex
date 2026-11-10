defmodule Delivest.Background.Registry do
  @moduledoc "Allowlist of optional calculations; add consumers here when implemented."
  @tasks %{
    "marketing.preview" => %{
      feature: "marketing_policies",
      handler: Delivest.Marketing.Preview,
      interval: 86_400,
      scope: :franchise,
      timeout: :timer.minutes(2),
      statement_timeout: :timer.seconds(20)
    },
    "marketing.report" => %{
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
      feature: "marketing_policies",
      handler: Delivest.Marketing.Evaluate,
      interval: 86_400,
      scope: :franchise,
      timeout: :timer.minutes(2),
      statement_timeout: :timer.seconds(20)
    },
    "segments.refresh" => %{
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
