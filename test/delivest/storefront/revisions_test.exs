defmodule Delivest.Storefront.RevisionsTest do
  use ExUnit.Case, async: false

  alias Delivest.Repo
  alias Delivest.Storefront.Revisions

  test "independent transactions and compaction preserve the effective revision" do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      scope = Ecto.UUID.generate()
      options = Keyword.take(Repo.config(), [:hostname, :port, :username, :password, :database])
      {:ok, first} = Postgrex.start_link(options)
      {:ok, second} = Postgrex.start_link(options)

      try do
        Postgrex.query!(first, "SET statement_timeout = '2s'", [])
        Postgrex.query!(second, "SET statement_timeout = '2s'", [])
        Postgrex.query!(first, "BEGIN", [])
        Postgrex.query!(second, "BEGIN", [])
        Postgrex.query!(first, "SELECT storefront_record_revision('menu', $1)", [scope])
        Postgrex.query!(second, "SELECT storefront_record_revision('menu', $1)", [scope])

        assert revision(scope) == 0
        Postgrex.query!(second, "COMMIT", [])
        assert revision(scope) == 1
        Postgrex.query!(first, "COMMIT", [])
        assert revision(scope) == 2

        assert pending(scope) == 2
        assert {:ok, 1} = Revisions.compact(1)
        assert revision(scope) == 2
        assert {:ok, compacted} = Revisions.compact(10_000)
        assert compacted >= 1
        assert pending(scope) == 0
        assert revision(scope) == 2
      after
        Postgrex.query(first, "ROLLBACK", [])
        Postgrex.query(second, "ROLLBACK", [])

        Postgrex.query!(
          first,
          "DELETE FROM storefront_revision_pending WHERE section = 'menu' AND scope = $1",
          [scope]
        )

        Postgrex.query!(
          first,
          "DELETE FROM storefront_revisions WHERE section = 'menu' AND scope = $1",
          [scope]
        )

        GenServer.stop(first)
        GenServer.stop(second)
      end
    end)
  end

  defp revision(scope) do
    [[value]] =
      Repo.query!(
        """
        SELECT COALESCE(SUM(revision), 0)::bigint FROM (
          SELECT revision FROM storefront_revisions WHERE section = 'menu' AND scope = $1
          UNION ALL
          SELECT delta FROM storefront_revision_pending WHERE section = 'menu' AND scope = $1
        ) changes
        """,
        [scope]
      ).rows

    value
  end

  defp pending(scope) do
    [[count]] =
      Repo.query!(
        "SELECT COUNT(*) FROM storefront_revision_pending WHERE section = 'menu' AND scope = $1",
        [scope]
      ).rows

    count
  end
end
