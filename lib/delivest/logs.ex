defmodule Delivest.Logs do
  import Ecto.Query, warn: false

  alias Delivest.Logs.Entry
  alias Delivest.Repo

  @levels %{errors: ~w(error critical alert emergency)}

  def config, do: Application.get_env(:delivest, __MODULE__, [])

  def enabled?, do: Keyword.get(config(), :enabled, true)

  def level, do: Keyword.get(config(), :level, :info)

  def retention_days, do: Keyword.get(config(), :retention_days, 14)

  def list_entries(scope, params \\ %{}) do
    Entry
    |> scope(scope)
    |> Flop.validate_and_run(params, for: Entry)
  end

  def prune(days) do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day)
    Repo.delete_all(from(e in Entry, where: e.inserted_at < ^cutoff))
  end

  defp scope(query, :raw), do: query

  defp scope(query, scope), do: where(query, [e], e.level in ^Map.fetch!(@levels, scope))
end
