defmodule Delivest.Repo.Migrations.AddSegments do
  use Ecto.Migration

  def change do
    create table(:segments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :kind, :string, null: false
      add :scope, :string, null: false
      add :rules, :map
      add :revision, :integer, null: false, default: 1
      add :published_snapshot_id, :binary_id
      add :last_refreshed_at, :utc_datetime
      add :last_refresh_error, :string
      timestamps(type: :utc_datetime)
    end

    create constraint(:segments, :segments_kind_check, check: "kind IN ('manual', 'dynamic')")

    create constraint(:segments, :segments_scope_check,
             check: "scope IN ('franchise', 'branches')"
           )

    create table(:segment_branches, primary_key: false) do
      add :segment_id, references(:segments, type: :binary_id, on_delete: :delete_all),
        null: false

      add :branch_id, references(:branches, type: :binary_id, on_delete: :delete_all), null: false
    end

    create unique_index(:segment_branches, [:segment_id, :branch_id])
    create index(:segment_branches, [:branch_id])

    create table(:segment_manual_members, primary_key: false) do
      add :segment_id, references(:segments, type: :binary_id, on_delete: :delete_all),
        null: false

      add :client_id, references(:clients, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:segment_manual_members, [:segment_id, :client_id])

    create table(:segment_customer_metrics, primary_key: false) do
      add :snapshot_id, :binary_id, null: false
      add :branch_id, references(:branches, type: :binary_id, on_delete: :delete_all), null: false
      add :client_id, references(:clients, type: :binary_id, on_delete: :delete_all), null: false
      add :order_count, :integer, null: false
      add :total_spent, :bigint, null: false
      add :last_order_at, :utc_datetime
    end

    create unique_index(:segment_customer_metrics, [:snapshot_id, :client_id, :branch_id],
             name: :segment_customer_metrics_key
           )

    create table(:segment_metric_states, primary_key: false) do
      add :branch_id, references(:branches, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :snapshot_id, :binary_id
      add :feature_generation, :integer
      add :parent_generation, :integer
      add :last_refreshed_at, :utc_datetime
    end

    execute(
      "CREATE SEQUENCE segment_dirty_revision_seq",
      "DROP SEQUENCE segment_dirty_revision_seq"
    )

    create table(:segment_dirty_clients, primary_key: false) do
      add :branch_id, references(:branches, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :client_id, references(:clients, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :revision, :bigint, null: false
    end

    create table(:segment_dirty_ack, primary_key: false) do
      add :snapshot_id, :binary_id, primary_key: true

      add :branch_id, references(:branches, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :client_id, references(:clients, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :revision, :bigint, null: false
    end

    create index(:segment_dirty_ack, [:snapshot_id, :branch_id])

    create table(:segment_dynamic_members, primary_key: false) do
      add :segment_id, references(:segments, type: :binary_id, on_delete: :delete_all),
        null: false

      add :snapshot_id, :binary_id, null: false
      add :client_id, references(:clients, type: :binary_id, on_delete: :delete_all), null: false
    end

    create unique_index(:segment_dynamic_members, [:segment_id, :snapshot_id, :client_id],
             name: :segment_dynamic_members_key
           )

    create index(:segment_dynamic_members, [:segment_id, :client_id])

    execute(
      """
      CREATE OR REPLACE FUNCTION segment_mark_dirty(p_branch uuid, p_client uuid)
      RETURNS void LANGUAGE plpgsql AS $$
      BEGIN
        IF p_branch IS NULL OR p_client IS NULL THEN RETURN; END IF;
        IF NOT EXISTS (
          SELECT 1 FROM feature_gates p JOIN feature_gates b
            ON b.feature = p.feature AND b.scope_key = 'branch:' || p_branch::text
          WHERE p.feature = 'segments' AND p.scope_key = 'franchise'
            AND p.enabled AND b.enabled
        ) THEN RETURN; END IF;
        INSERT INTO segment_dirty_clients(branch_id, client_id, revision)
        VALUES (p_branch, p_client, nextval('segment_dirty_revision_seq'))
        ON CONFLICT (branch_id, client_id) DO UPDATE
          SET revision = nextval('segment_dirty_revision_seq');
      END $$;
      """,
      "DROP FUNCTION segment_mark_dirty(uuid, uuid)"
    )

    execute(
      """
      CREATE OR REPLACE FUNCTION segment_order_dirty_trigger()
      RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP = 'UPDATE' AND
           (OLD.branch_id, OLD.client_id, OLD.status, OLD.total_amount, OLD.deleted_at, OLD.inserted_at)
           IS NOT DISTINCT FROM
           (NEW.branch_id, NEW.client_id, NEW.status, NEW.total_amount, NEW.deleted_at, NEW.inserted_at)
        THEN RETURN NULL; END IF;
        IF TG_OP IN ('UPDATE', 'DELETE') THEN
          PERFORM segment_mark_dirty(OLD.branch_id, OLD.client_id);
        END IF;
        IF TG_OP IN ('INSERT', 'UPDATE') THEN
          IF TG_OP = 'INSERT' OR (OLD.branch_id, OLD.client_id) IS DISTINCT FROM (NEW.branch_id, NEW.client_id)
          THEN PERFORM segment_mark_dirty(NEW.branch_id, NEW.client_id); END IF;
        END IF;
        RETURN NULL;
      END $$;
      """,
      "DROP FUNCTION segment_order_dirty_trigger()"
    )

    execute(
      """
      CREATE TRIGGER segment_orders_dirty AFTER INSERT OR UPDATE OR DELETE ON orders
      FOR EACH ROW EXECUTE FUNCTION segment_order_dirty_trigger();
      """,
      "DROP TRIGGER segment_orders_dirty ON orders"
    )

    execute(
      """
      CREATE OR REPLACE FUNCTION segment_refund_dirty_trigger()
      RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE source_order record;
      BEGIN
        IF TG_OP = 'UPDATE' AND
           (OLD.order_id, OLD.amount, OLD.status) IS NOT DISTINCT FROM
           (NEW.order_id, NEW.amount, NEW.status)
        THEN RETURN NULL; END IF;
        IF TG_OP IN ('UPDATE', 'DELETE') THEN
          SELECT branch_id, client_id INTO source_order FROM orders WHERE id = OLD.order_id;
          IF FOUND THEN PERFORM segment_mark_dirty(source_order.branch_id, source_order.client_id); END IF;
        END IF;
        IF TG_OP IN ('INSERT', 'UPDATE') THEN
          SELECT branch_id, client_id INTO source_order FROM orders WHERE id = NEW.order_id;
          IF FOUND THEN PERFORM segment_mark_dirty(source_order.branch_id, source_order.client_id); END IF;
        END IF;
        RETURN NULL;
      END $$;
      """,
      "DROP FUNCTION segment_refund_dirty_trigger()"
    )

    execute(
      """
      CREATE TRIGGER segment_refunds_dirty AFTER INSERT OR UPDATE OR DELETE ON order_refunds
      FOR EACH ROW EXECUTE FUNCTION segment_refund_dirty_trigger();
      """,
      "DROP TRIGGER segment_refunds_dirty ON order_refunds"
    )
  end
end
