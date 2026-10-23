defmodule Delivest.Logs do
  import Ecto.Query, warn: false

  alias Delivest.Logs.Entry
  alias Delivest.Repo

  @levels %{errors: ~w(error critical alert emergency)}

  def config, do: Application.get_env(:delivest, __MODULE__, [])

  def enabled?, do: Keyword.get(config(), :enabled, true)

  def level, do: Keyword.get(config(), :level, :info)

  def retention_days, do: Keyword.get(config(), :retention_days, 7)

  def error_retention_days, do: Keyword.get(config(), :error_retention_days, 30)

  def list_entries(scope, params \\ %{}) do
    Entry
    |> scope(scope)
    |> Flop.validate_and_run(params, for: Entry)
  end

  def prune(days, error_days) do
    {raw, _} = Entry |> where([e], e.level not in ^@levels.errors) |> delete_before(days)
    {errors, _} = Entry |> scope(:errors) |> delete_before(error_days)
    raw + errors
  end

  defp delete_before(query, days) do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day)
    query |> where([e], e.inserted_at < ^cutoff) |> Repo.delete_all()
  end

  defp scope(query, :raw), do: query

  defp scope(query, scope), do: where(query, [e], e.level in ^Map.fetch!(@levels, scope))
end
