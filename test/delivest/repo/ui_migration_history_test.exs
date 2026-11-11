defmodule Delivest.Repo.UiMigrationHistoryTest do
  use Delivest.DataCase, async: false

  alias Delivest.Repo.UiMigrationHistory
  alias Ecto.Adapters.SQL

  @old [20_261_210_000_022, 20_261_210_000_023, 20_261_210_000_024]
  @new [20_261_210_000_035, 20_261_210_000_036, 20_261_210_000_037]

  defp isolated_schema(fun) do
    schema = "ui_migration_#{System.unique_integer([:positive])}"

    Repo.transaction(fn ->
      SQL.query!(Repo, "CREATE SCHEMA #{schema}", [])
      SQL.query!(Repo, "SET LOCAL search_path TO #{schema}", [])
      fun.()
    end)
  end

  defp history(versions) do
    SQL.query!(
      Repo,
      "CREATE TABLE schema_migrations (version bigint PRIMARY KEY, inserted_at timestamp NOT NULL)",
      []
    )

    Enum.each(versions, fn version ->
      SQL.query!(Repo, "INSERT INTO schema_migrations VALUES ($1, '2020-01-01')", [version])
    end)
  end

  defp tables(names) do
    Enum.each(names, fn name -> SQL.query!(Repo, "CREATE TABLE #{name} (id bigint)", []) end)
  end

  defp versions do
    SQL.query!(Repo, "SELECT version FROM schema_migrations ORDER BY version", []).rows
    |> List.flatten()
  end

  test "fresh schema without migration history is untouched" do
    assert {:ok, :ok} = isolated_schema(fn -> UiMigrationHistory.prepare!(Repo) end)
  end

  test "canonical F04 history remains at versions 22 through 24" do
    assert {:ok, :ok} =
             isolated_schema(fn ->
               history(@old)

               tables(
                 ~w(feature_gates background_schedules segments segment_branches marketing_policies)
               )

               assert :ok = UiMigrationHistory.prepare!(Repo)
               assert versions() == @old
               :ok
             end)
  end

  test "seven-task history moves only version metadata and preserves inserted_at" do
    assert {:ok, :ok} =
             isolated_schema(fn ->
               history(@old)
               tables(~w(product_operation_mappings daily_runs frontpad_stop_refresh_states))
               assert :ok = UiMigrationHistory.prepare!(Repo)
               assert versions() == @new

               assert SQL.query!(Repo, "SELECT DISTINCT inserted_at FROM schema_migrations", []).rows ==
                        [[~N[2020-01-01 00:00:00.000000]]]

               assert :ok = UiMigrationHistory.prepare!(Repo)
               assert versions() == @new
               :ok
             end)
  end

  test "mixed partial history is reassigned per version" do
    assert {:ok, :ok} =
             isolated_schema(fn ->
               history(@old)

               tables(
                 ~w(feature_gates background_schedules daily_runs frontpad_stop_refresh_states)
               )

               assert :ok = UiMigrationHistory.prepare!(Repo)
               assert versions() == [hd(@old), Enum.at(@new, 1), Enum.at(@new, 2)]
               :ok
             end)
  end

  test "canonical and task tables are accepted only when the new version is recorded" do
    assert {:ok, :ok} =
             isolated_schema(fn ->
               history([hd(@old), hd(@new)])
               tables(~w(feature_gates background_schedules product_operation_mappings))
               assert :ok = UiMigrationHistory.prepare!(Repo)
               assert versions() == [hd(@old), hd(@new)]
               :ok
             end)
  end

  test "ambiguous history fails atomically" do
    assert_raise RuntimeError, ~r/ambiguous UI migration history/, fn ->
      isolated_schema(fn ->
        history([hd(@old), Enum.at(@old, 1)])
        tables(~w(feature_gates background_schedules product_operation_mappings daily_runs))
        UiMigrationHistory.prepare!(Repo)
      end)
    end
  end
end
