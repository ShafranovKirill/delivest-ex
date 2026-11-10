defmodule Delivest.Background.Registry do
  @moduledoc "Allowlist of optional calculations; add consumers here when implemented."
  @tasks %{
    "segments.refresh" => %{
      feature: "segments",
      handler: Delivest.Segments.Refresh,
      interval: 86_400
    }
  }

  def fetch(kind), do: Map.fetch(@tasks, kind)
end
