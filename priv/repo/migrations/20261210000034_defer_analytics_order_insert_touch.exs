defmodule Delivest.Repo.Migrations.DeferAnalyticsOrderInsertTouch do
  use Ecto.Migration

  def up do
    execute "DROP TRIGGER analytics_orders_touch ON orders"

    execute """
    CREATE TRIGGER analytics_orders_touch
    AFTER UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION analytics_touch_order()
    """

    # The order's receipts and source claim are written later in the same transaction.
    # Touching report state here would invert the source-claim advisory lock order.
    execute """
    CREATE CONSTRAINT TRIGGER analytics_orders_insert_touch
    AFTER INSERT ON orders
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION analytics_touch_order()
    """

    execute """
    CREATE OR REPLACE FUNCTION analytics_touch_order() RETURNS trigger LANGUAGE plpgsql AS $$
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
      PERFORM analytics_touch_day(order_row.branch_id, COALESCE(cohort_at, order_row.inserted_at), 'analytics_funnel');
      PERFORM analytics_touch_day(order_row.branch_id, order_row.inserted_at, 'analytics_links');
      RETURN NEW;
    END $$;
    """
  end

  def down do
    execute "DROP TRIGGER analytics_orders_insert_touch ON orders"
    execute "DROP TRIGGER analytics_orders_touch ON orders"

    execute """
    CREATE TRIGGER analytics_orders_touch
    AFTER INSERT OR UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION analytics_touch_order()
    """

    execute """
    CREATE OR REPLACE FUNCTION analytics_touch_order() RETURNS trigger LANGUAGE plpgsql AS $$
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
    """
  end
end
