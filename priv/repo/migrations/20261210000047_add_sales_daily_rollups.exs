defmodule Delivest.Repo.Migrations.AddSalesDailyRollups do
  use Ecto.Migration

  def up do
    create table(:sales_daily_rollups, primary_key: false) do
      add :branch_id, :uuid, primary_key: true
      add :day, :date, primary_key: true
      add :timezone, :text, null: false, default: ""
      add :revision, :bigint, null: false, default: 0
      add :dirty, :boolean, null: false, default: true
      add :payload, :map
      add :computed_at, :utc_datetime_usec
    end

    create index(:sales_daily_rollups, [:day], where: "dirty")

    statements = """
    CREATE FUNCTION sales_touch_day(p_branch uuid, p_at timestamp without time zone)
    RETURNS void LANGUAGE plpgsql AS $$
    DECLARE zone text; local_day date;
    BEGIN
      IF p_branch IS NULL OR p_at IS NULL THEN RETURN; END IF;
      SELECT COALESCE((SELECT timezone FROM branch_info WHERE branch_id=p_branch),
        (SELECT timezone FROM franchise_settings LIMIT 1),'Europe/Moscow') INTO zone;
      local_day := (p_at AT TIME ZONE 'UTC' AT TIME ZONE zone)::date;
      INSERT INTO sales_daily_rollups(branch_id,day,revision,dirty)
      VALUES (p_branch,local_day,1,true)
      ON CONFLICT (branch_id,day) DO UPDATE SET revision=sales_daily_rollups.revision+1,dirty=true;
    END $$;

    CREATE FUNCTION sales_touch_order() RETURNS trigger LANGUAGE plpgsql AS $$
    DECLARE source_order orders%ROWTYPE;
    BEGIN
      IF TG_TABLE_NAME='orders' THEN
        IF TG_OP <> 'INSERT' THEN PERFORM sales_touch_day(OLD.branch_id,OLD.inserted_at); END IF;
        IF TG_OP <> 'DELETE' THEN PERFORM sales_touch_day(NEW.branch_id,NEW.inserted_at); END IF;
      ELSE
        IF TG_OP <> 'INSERT' THEN
          SELECT * INTO source_order FROM orders WHERE id=OLD.order_id;
          PERFORM sales_touch_day(source_order.branch_id,source_order.inserted_at);
        END IF;
        IF TG_OP <> 'DELETE' THEN
          SELECT * INTO source_order FROM orders WHERE id=NEW.order_id;
          PERFORM sales_touch_day(source_order.branch_id,source_order.inserted_at);
        END IF;
      END IF;
      RETURN NULL;
    END $$;

    CREATE TRIGGER sales_order_dirty AFTER INSERT OR UPDATE OR DELETE ON orders
      FOR EACH ROW EXECUTE FUNCTION sales_touch_order();
    CREATE TRIGGER sales_item_dirty AFTER INSERT OR UPDATE OR DELETE ON order_items
      FOR EACH ROW EXECUTE FUNCTION sales_touch_order();

    CREATE FUNCTION sales_timezone_dirty() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF TG_TABLE_NAME='branch_info' THEN
        IF TG_OP <> 'INSERT' THEN
          UPDATE sales_daily_rollups SET dirty=true,revision=revision+1,timezone='' WHERE branch_id=OLD.branch_id;
        END IF;
        IF TG_OP <> 'DELETE' THEN
          UPDATE sales_daily_rollups SET dirty=true,revision=revision+1,timezone='' WHERE branch_id=NEW.branch_id;
        END IF;
      ELSE
        UPDATE sales_daily_rollups SET dirty=true,revision=revision+1,timezone='';
      END IF;
      RETURN NULL;
    END $$;
    CREATE TRIGGER sales_branch_timezone_dirty AFTER INSERT OR UPDATE OF timezone OR DELETE ON branch_info
      FOR EACH ROW EXECUTE FUNCTION sales_timezone_dirty();
    CREATE TRIGGER sales_franchise_timezone_dirty AFTER UPDATE OF timezone ON franchise_settings
      FOR EACH ROW EXECUTE FUNCTION sales_timezone_dirty();
    """

    for statement <- String.split(statements, ~r/;\n\s*(?=CREATE)/) do
      execute statement
    end
  end

  def down do
    statements = """
    DROP TRIGGER sales_franchise_timezone_dirty ON franchise_settings;
    DROP TRIGGER sales_branch_timezone_dirty ON branch_info;
    DROP TRIGGER sales_item_dirty ON order_items;
    DROP TRIGGER sales_order_dirty ON orders;
    DROP FUNCTION sales_timezone_dirty();
    DROP FUNCTION sales_touch_order();
    DROP FUNCTION sales_touch_day(uuid,timestamp without time zone);
    """

    for statement <- String.split(statements, ";", trim: true), do: execute(statement)

    drop table(:sales_daily_rollups)
  end
end
