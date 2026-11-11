defmodule Delivest.Repo.Migrations.AnalyticsReportBuckets do
  use Ecto.Migration

  def change do
    execute """
    UPDATE roles SET permissions=permissions || '["statistics.network"]'::jsonb,
      updated_at=timezone('UTC', now())
    WHERE name='Управляющий франшизой' AND NOT permissions ? 'statistics.network'
    """, """
    UPDATE roles SET permissions=permissions - 'statistics.network',
      updated_at=timezone('UTC', now())
    WHERE name='Управляющий франшизой'
    """

    create table(:analytics_order_identities, primary_key: false) do
      add :order_id, references(:orders, type: :uuid), primary_key: true
      add :verified_client_id, references(:clients, type: :uuid)
      add :owner_kind, :string, null: false
      add :as_of_at, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create constraint(:analytics_order_identities, :analytics_order_identities_owner_kind_check,
             check: "owner_kind IN ('client', 'guest', 'unknown')"
           )

    create table(:analytics_report_states, primary_key: false) do
      add :feature, :string, null: false
      add :branch_id, references(:branches, type: :uuid), null: false
      add :day, :date, null: false
      add :revision, :bigint, null: false, default: 0
      add :snapshot_id, :uuid
      add :published_at, :utc_datetime_usec
      add :source_asof, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:analytics_report_states, [:feature, :branch_id, :day])
    create index(:analytics_report_states, [:branch_id, :day])

    create table(:analytics_report_snapshots, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :feature, :string, null: false
      add :branch_id, references(:branches, type: :uuid), null: false
      add :day, :date, null: false
      add :revision, :bigint, null: false
      add :franchise_generation, :bigint, null: false
      add :branch_generation, :bigint, null: false
      add :source_asof, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:analytics_report_snapshots, [:feature, :branch_id, :day])

    create table(:analytics_report_rows, primary_key: false) do
      add :snapshot_id,
          references(:analytics_report_snapshots, type: :uuid, on_delete: :delete_all),
          null: false

      add :family, :string, null: false
      add :dimension, :string, null: false
      add :key, :string, null: false
      add :counts, :map, null: false, default: %{}
    end

    create unique_index(:analytics_report_rows, [:snapshot_id, :family, :dimension, :key])
    create index(:analytics_report_rows, [:family, :dimension, :key])
    create index(:funnel_sessions, [:branch_id, :started_at])
    create index(:funnel_order_receipts, [:session_started_at])
    create index(:advertising_clicks, [:branch_id, :clicked_at])
    create index(:client_first_sources, [:landing_branch_id, :clicked_at])

    execute """
            CREATE FUNCTION analytics_touch_day(p_branch uuid, p_at timestamp without time zone, p_feature text)
            RETURNS void LANGUAGE plpgsql AS $$
            DECLARE local_day date;
            BEGIN
              IF p_branch IS NULL OR p_at IS NULL OR NOT EXISTS (
                SELECT 1 FROM feature_gates f JOIN feature_gates b ON b.feature=f.feature
                WHERE f.feature=p_feature AND f.scope_key='franchise' AND f.enabled
                  AND b.scope_key='branch:' || p_branch::text AND b.enabled
              ) THEN RETURN; END IF;
              SELECT (p_at AT TIME ZONE 'UTC' AT TIME ZONE COALESCE(i.timezone, (SELECT timezone FROM franchise_settings LIMIT 1), 'Europe/Moscow'))::date
              INTO local_day FROM branches br
              LEFT JOIN branch_info i ON i.branch_id=br.id
              WHERE br.id=p_branch LIMIT 1;
              IF local_day IS NULL THEN RETURN; END IF;
              INSERT INTO analytics_report_states (feature, branch_id, day, revision, inserted_at, updated_at)
              VALUES (p_feature, p_branch, local_day, 1, timezone('UTC', now()), timezone('UTC', now()))
              ON CONFLICT (feature, branch_id, day)
              DO UPDATE SET revision=analytics_report_states.revision+1, updated_at=timezone('UTC', now());
            END $$;
            """,
            "DROP FUNCTION analytics_touch_day(uuid, timestamp without time zone, text)"

    execute """
            CREATE FUNCTION analytics_touch_order() RETURNS trigger LANGUAGE plpgsql AS $$
            DECLARE order_row orders%ROWTYPE; cohort_at timestamp without time zone;
            BEGIN
              IF TG_TABLE_NAME='orders' THEN
                IF TG_OP='UPDATE' THEN
                  PERFORM analytics_touch_day(OLD.branch_id, OLD.inserted_at, 'analytics_extended');
                  PERFORM analytics_touch_day(OLD.branch_id, OLD.inserted_at, 'analytics_links');
                END IF;
                order_row := NEW;
              ELSE
                SELECT * INTO order_row FROM orders WHERE id=NEW.order_id;
              END IF;
              PERFORM analytics_touch_day(order_row.branch_id, order_row.inserted_at, 'analytics_extended');
            SELECT session_started_at INTO cohort_at FROM funnel_order_receipts WHERE order_id=order_row.id;
            IF cohort_at IS NOT NULL THEN
            PERFORM analytics_touch_day(order_row.branch_id, cohort_at, 'analytics_funnel');
            END IF;
              PERFORM analytics_touch_day(order_row.branch_id, order_row.inserted_at, 'analytics_links');
              RETURN NEW;
            END $$;
            """,
            "DROP FUNCTION analytics_touch_order()"

    create constraint(:analytics_report_states, :analytics_report_states_revision_nonnegative,
             check: "revision >= 0"
           )

    execute "CREATE TRIGGER analytics_orders_touch AFTER INSERT OR UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION analytics_touch_order()",
            "DROP TRIGGER analytics_orders_touch ON orders"

    execute "CREATE TRIGGER analytics_payments_touch AFTER INSERT OR UPDATE ON order_payments FOR EACH ROW EXECUTE FUNCTION analytics_touch_order()",
            "DROP TRIGGER analytics_payments_touch ON order_payments"

    execute "CREATE TRIGGER analytics_refunds_touch AFTER INSERT OR UPDATE ON order_refunds FOR EACH ROW EXECUTE FUNCTION analytics_touch_order()",
            "DROP TRIGGER analytics_refunds_touch ON order_refunds"

    execute """
    CREATE FUNCTION analytics_touch_funnel() RETURNS trigger LANGUAGE plpgsql AS $$
    DECLARE cohort_at timestamp without time zone;
            BEGIN
      SELECT started_at INTO cohort_at FROM funnel_sessions WHERE id=NEW.session_id;
      PERFORM analytics_touch_day(NEW.branch_id, cohort_at, 'analytics_funnel');
              RETURN NEW;
            END $$;
            """,
            "DROP FUNCTION analytics_touch_funnel()"

    execute "CREATE TRIGGER analytics_funnel_touch AFTER INSERT ON funnel_events FOR EACH ROW EXECUTE FUNCTION analytics_touch_funnel()",
            "DROP TRIGGER analytics_funnel_touch ON funnel_events"

    execute """
            CREATE FUNCTION analytics_touch_receipt() RETURNS trigger LANGUAGE plpgsql AS $$
            DECLARE o orders%ROWTYPE;
            BEGIN
              SELECT * INTO o FROM orders WHERE id=NEW.order_id;
              IF TG_TABLE_NAME='analytics_order_identities' THEN
                PERFORM analytics_touch_day(o.branch_id, o.inserted_at, 'analytics_extended');
              ELSIF TG_TABLE_NAME='funnel_order_receipts' THEN
                PERFORM analytics_touch_day(o.branch_id, NEW.session_started_at, 'analytics_funnel');
                PERFORM analytics_touch_day(o.branch_id, o.inserted_at, 'analytics_extended');
              ELSE
                PERFORM analytics_touch_day(o.branch_id, o.inserted_at, 'analytics_links');
              END IF;
              RETURN NEW;
            END $$;
            """,
            "DROP FUNCTION analytics_touch_receipt()"

    execute "CREATE TRIGGER analytics_funnel_receipt_touch AFTER INSERT ON funnel_order_receipts FOR EACH ROW EXECUTE FUNCTION analytics_touch_receipt()",
            "DROP TRIGGER analytics_funnel_receipt_touch ON funnel_order_receipts"

    execute "CREATE TRIGGER analytics_identity_receipt_touch AFTER INSERT ON analytics_order_identities FOR EACH ROW EXECUTE FUNCTION analytics_touch_receipt()",
            "DROP TRIGGER analytics_identity_receipt_touch ON analytics_order_identities"

    execute "CREATE TRIGGER analytics_link_receipt_touch AFTER INSERT ON advertising_order_receipts FOR EACH ROW EXECUTE FUNCTION analytics_touch_receipt()",
            "DROP TRIGGER analytics_link_receipt_touch ON advertising_order_receipts"

    execute """
            CREATE FUNCTION analytics_touch_click() RETURNS trigger LANGUAGE plpgsql AS $$
            BEGIN
              PERFORM analytics_touch_day(NEW.branch_id, NEW.clicked_at, 'analytics_links');
              RETURN NEW;
            END $$;
            """,
            "DROP FUNCTION analytics_touch_click()"

    execute "CREATE TRIGGER analytics_click_touch AFTER INSERT ON advertising_clicks FOR EACH ROW EXECUTE FUNCTION analytics_touch_click()",
            "DROP TRIGGER analytics_click_touch ON advertising_clicks"

    execute """
            CREATE FUNCTION analytics_touch_first_source() RETURNS trigger LANGUAGE plpgsql AS $$
            BEGIN
              PERFORM analytics_touch_day(NEW.landing_branch_id, NEW.clicked_at, 'analytics_links');
              RETURN NEW;
            END $$;
            """,
            "DROP FUNCTION analytics_touch_first_source()"

    execute "CREATE TRIGGER analytics_first_source_touch AFTER INSERT ON client_first_sources FOR EACH ROW EXECUTE FUNCTION analytics_touch_first_source()",
            "DROP TRIGGER analytics_first_source_touch ON client_first_sources"
  end
end
