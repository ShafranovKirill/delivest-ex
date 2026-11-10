defmodule Delivest.Background.Registry do
  @moduledoc "Allowlist of optional calculations; add consumers here when implemented."
  @tasks %{
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
end
