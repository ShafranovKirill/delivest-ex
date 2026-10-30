defmodule Delivest.Repo.Migrations.AddPaymentsToBranchInfo do
  use Ecto.Migration

  @grants [
    {"branches.read", ["finance.read"]},
    {"branches.update", ["finance.update"]}
  ]

  def up do
    alter table(:branch_info) do
      add :payments, :map, default: %{}, null: false
    end

    Enum.each(@grants, fn {source, added} ->
      execute("""
      UPDATE roles
      SET permissions = (
        SELECT jsonb_agg(DISTINCT permission)
        FROM jsonb_array_elements_text(permissions || '#{Jason.encode!(added)}'::jsonb) permission
      )
      WHERE permissions @> '#{Jason.encode!([source])}'::jsonb
      """)
    end)
  end

  def down do
    alter table(:branch_info) do
      remove :payments
    end
  end
end
