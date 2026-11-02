Code.require_file(
  "../../../priv/repo/migrations/20261102200722_reset_ambiguous_integration_health.exs",
  __DIR__
)

defmodule Delivest.Integrations.HealthMigrationTest do
  use Delivest.DataCase, async: true

  alias Delivest.Repo
  alias Delivest.Repo.Migrations.ResetAmbiguousIntegrationHealth

  @table "integration_health"

  defp insert_row(provider, attrs) do
    id = Ecto.UUID.generate()

    attrs =
      Map.merge(
        %{
          id: Ecto.UUID.dump!(id),
          provider: provider,
          branch_id: Ecto.UUID.dump!(Ecto.UUID.generate()),
          status: nil,
          message: nil,
          checked_at: nil,
          warning: nil,
          warning_at: nil
        },
        attrs
      )

    {1, _rows} = Repo.insert_all(@table, [attrs])
    id
  end

  defp row(id) do
    Repo.one(
      from(h in "integration_health",
        where: h.id == type(^id, Ecto.UUID),
        select:
          map(h, [
            :status,
            :message,
            :checked_at,
            :warning,
            :warning_at
          ])
      )
    )
  end

  test "a legacy warning keeps its text and time but proves no connection" do
    at = ~N[2026-10-01 12:00:00.000000]

    id =
      insert_row("frontpad", %{
        status: "warning",
        message: "catalog_issues:2",
        checked_at: at
      })

    Repo.query!(ResetAmbiguousIntegrationHealth.legacy_warning_sql())

    assert %{
             status: nil,
             message: nil,
             checked_at: nil,
             warning: "catalog_issues:2",
             warning_at: ^at
           } = row(id)
  end

  test "an ok row with a warning after the first migration becomes unknown" do
    checked_at = ~N[2026-10-02 09:00:00.000000]
    warning_at = ~N[2026-10-03 10:00:00.000000]

    id =
      insert_row("iiko", %{
        status: "ok",
        checked_at: checked_at,
        warning: "catalog_issues:4",
        warning_at: warning_at
      })

    Repo.query!(ResetAmbiguousIntegrationHealth.ambiguous_ok_sql())

    assert %{
             status: nil,
             checked_at: nil,
             warning: "catalog_issues:4",
             warning_at: ^warning_at
           } = row(id)
  end

  test "proven results survive and a failure can keep its warning" do
    ok_at = ~N[2026-10-04 11:00:00.000000]
    auth_at = ~N[2026-10-04 12:00:00.000000]
    failed_at = ~N[2026-10-04 13:00:00.000000]
    warning_at = ~N[2026-10-04 14:00:00.000000]

    ok = insert_row("rkeeper", %{status: "ok", checked_at: ok_at})
    auth = insert_row("yookassa", %{status: "auth", message: "401", checked_at: auth_at})

    failed =
      insert_row("atol", %{
        status: "failed",
        message: "timeout",
        checked_at: failed_at,
        warning: "kkt_issues:offline",
        warning_at: warning_at
      })

    Repo.query!(ResetAmbiguousIntegrationHealth.legacy_warning_sql())
    Repo.query!(ResetAmbiguousIntegrationHealth.ambiguous_ok_sql())

    assert %{status: "ok", checked_at: ^ok_at, warning: nil} = row(ok)

    assert %{status: "auth", message: "401", checked_at: ^auth_at, warning: nil} =
             row(auth)

    assert %{
             status: "failed",
             message: "timeout",
             checked_at: ^failed_at,
             warning: "kkt_issues:offline",
             warning_at: ^warning_at
           } = row(failed)
  end
end
