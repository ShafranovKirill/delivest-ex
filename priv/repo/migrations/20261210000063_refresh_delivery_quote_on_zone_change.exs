defmodule Delivest.Repo.Migrations.RefreshDeliveryQuoteOnZoneChange do
  use Ecto.Migration

  def change do
    execute(
      "CREATE TRIGGER order_timing_zone_revision AFTER INSERT OR UPDATE OR DELETE ON delivery_zones FOR EACH ROW EXECUTE FUNCTION storefront_bump_revision('branches', 'branch_id')",
      "DROP TRIGGER order_timing_zone_revision ON delivery_zones"
    )

    execute(
      "CREATE TRIGGER order_timing_zone_truncate_revision AFTER TRUNCATE ON delivery_zones FOR EACH STATEMENT EXECUTE FUNCTION storefront_bump_revision('branches')",
      "DROP TRIGGER order_timing_zone_truncate_revision ON delivery_zones"
    )
  end
end
