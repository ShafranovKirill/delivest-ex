defmodule Delivest.Repo.Migrations.AddRefundSalesRollupDirty do
  use Ecto.Migration

  def up do
    execute """
    CREATE TRIGGER sales_refund_dirty AFTER INSERT OR UPDATE OR DELETE ON order_refunds
      FOR EACH ROW EXECUTE FUNCTION sales_touch_order()
    """
  end

  def down do
    execute "DROP TRIGGER sales_refund_dirty ON order_refunds"
  end
end
