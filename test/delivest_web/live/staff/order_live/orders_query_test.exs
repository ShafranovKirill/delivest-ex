defmodule DelivestWeb.Staff.OrderLive.OrdersQueryTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias DelivestWeb.Staff.OrderLive.OrdersQuery

  test "valid chart drilldown is retained and invalid hour is ignored" do
    branch = insert(:branch)

    parsed =
      OrdersQuery.parse(%{"period" => "today", "hour" => "18", "sold" => "true"}, branch.id)

    assert parsed.selected.hour == 18
    assert parsed.filters.hour == 18
    assert parsed.filters.sold
    assert parsed.query["hour"] == "18"
    assert parsed.query["sold"] == "true"

    invalid = OrdersQuery.parse(%{"hour" => "24", "sold" => "false"}, branch.id)
    assert invalid.filters.hour == nil
    refute invalid.filters.sold
    refute Map.has_key?(invalid.query, "hour")
    refute Map.has_key?(invalid.query, "sold")
  end
end
