defmodule Delivest.Repo.UiMigrationHistory do
  @moduledoc """
  Reassigns the three UI migration versions used by the seven-task branch before
  running the canonical F04 migrations at the same original versions.
  """

  alias Delivest.Repo
  alias Ecto.Adapters.SQL

  @versions [
    {20_261_210_000_022, 20_261_210_000_035, "product_operation_mappings",
     ["feature_gates", "background_schedules"]},
    {20_261_210_000_023, 20_261_210_000_036, "daily_runs", ["segments", "segment_branches"]},
    {20_261_210_000_024, 20_261_210_000_037, "frontpad_stop_refresh_states",
     ["marketing_policies"]}
  ]

  def prepare! do
    {:ok, result, _apps} = Ecto.Migrator.with_repo(Repo, &prepare!/1)
    result
  end

  def prepare!(Repo) do
    {:ok, result} =
      Repo.transaction(fn ->
        SQL.query!(Repo, "SELECT pg_advisory_xact_lock(2026, 12010)", [])

        if table_exists?("schema_migrations") do
          versions =
            SQL.query!(
              Repo,
              "SELECT version FROM schema_migrations WHERE version IN (20261210000022, 20261210000023, 20261210000024, 20261210000035, 20261210000036, 20261210000037) FOR UPDATE",
              []
            ).rows
            |> Enum.map(&hd/1)
            |> MapSet.new()

          Enum.each(@versions, &reassign(&1, versions))
        end

        :ok
      end)

    result
  end

  defp reassign({old, new, task_table, f04_tables}, versions) do
    if MapSet.member?(versions, old) do
      task_table? = table_exists?(task_table)
      f04_count = Enum.count(f04_tables, &table_exists?/1)
      new? = MapSet.member?(versions, new)

      case {task_table?, f04_count, new?} do
        {true, 0, false} ->
          SQL.query!(Repo, "UPDATE schema_migrations SET version = $1 WHERE version = $2", [
            new,
            old
          ])

        {false, count, _} when count == length(f04_tables) ->
          :ok

        {true, count, true} when count == length(f04_tables) ->
          :ok

        _ ->
          raise "ambiguous UI migration history at version #{old}"
      end
    end
  end

  defp table_exists?(table) do
    [[exists?]] = SQL.query!(Repo, "SELECT to_regclass($1) IS NOT NULL", [table]).rows
    exists?
  end
end
