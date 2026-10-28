defmodule Delivest.Repo.Migrations.CreateOrderTransitions do
  use Ecto.Migration

  @path ~w(created accepted preparing ready delivering completed)

  def up do
    create table(:order_transitions) do
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false
      add :from, :string
      add :to, :string, null: false
      add :source, :string, null: false
      add :staff_id, references(:staff, type: :binary_id, on_delete: :nilify_all)
      add :reason, :string
      add :reverted_at, :utc_datetime_usec
      add :reverted_by_id, references(:staff, type: :binary_id, on_delete: :nilify_all)
      add :revert_reason, :string

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:order_transitions, [:order_id, :id])
    create index(:order_transitions, [:to, :source], where: "reverted_at IS NULL")

    alter table(:orders) do
      add :cancel_acknowledged_at, :utc_datetime
    end

    execute("""
    UPDATE orders
    SET status = coalesce(
      crm->>'remote_status',
      CASE WHEN crm->>'status' = 'sent' THEN 'accepted' ELSE 'created' END
    )
    WHERE status = 'crm'
    """)

    execute("""
    UPDATE orders
    SET status = channel->>'remote_status'
    WHERE channel->>'remote_status' IS NOT NULL
      AND channel->>'remote_status' <> status
      AND (
        channel->>'remote_status' = 'cancelled'
        OR array_position(#{path_array()}, channel->>'remote_status') >
             coalesce(array_position(#{path_array()}, status), 0)
      )
    """)

    execute("""
    UPDATE roles
    SET permissions = (
      SELECT jsonb_agg(DISTINCT permission)
      FROM jsonb_array_elements_text(permissions || '["orders.cook", "orders.revert"]'::jsonb) permission
    )
    WHERE name = 'Управляющий'
    """)
  end

  def down do
    alter table(:orders) do
      remove :cancel_acknowledged_at
    end

    drop table(:order_transitions)
  end

  defp path_array, do: "ARRAY[#{Enum.map_join(@path, ", ", &"'#{&1}'")}]"
end
