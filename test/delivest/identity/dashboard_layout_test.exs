defmodule Delivest.Identity.DashboardLayoutTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Identity.DashboardLayout

  test "defaults are available without a stored row" do
    staff = insert(:staff)

    assert DashboardLayout.get(staff.id) == DashboardLayout.default()

    assert Enum.map(DashboardLayout.default().widgets, & &1.id) ==
             ~w(attention quick_actions revenue orders avg_check in_work hourly latest_orders top_products branch_summary)

    assert Enum.find(DashboardLayout.default().widgets, &(&1.id == "top_products")) ==
             %{id: "top_products", x: 0, y: 8, w: 6, h: 4}

    assert Enum.find(DashboardLayout.default().widgets, &(&1.id == "branch_summary")) ==
             %{id: "branch_summary", x: 6, y: 8, w: 6, h: 4}

    assert DashboardLayout.widget_limits("hourly").min_w == 4
    assert DashboardLayout.widget_limits("unknown") == nil
  end

  test "a layout saved before branch summary remains valid without adding a card" do
    staff = insert(:staff)
    old_widgets = Enum.reject(DashboardLayout.default().widgets, &(&1.id == "branch_summary"))
    assert {:ok, saved} = DashboardLayout.save(staff.id, %{widgets: old_widgets, actions: []})
    assert DashboardLayout.get(staff.id) == saved
    refute Enum.any?(saved.widgets, &(&1.id == "branch_summary"))
  end

  test "saves a canonical layout only for the selected staff member and resets it" do
    first = insert(:staff)
    second = insert(:staff)

    params = %{
      "widgets" => [%{"id" => "revenue", "x" => 9, "y" => 4, "w" => 3, "h" => 2}],
      "actions" => ["statistics", "orders"]
    }

    assert {:ok, canonical} = DashboardLayout.save(first.id, params)

    assert canonical == %{
             widgets: [%{id: "revenue", x: 9, y: 4, w: 3, h: 2}],
             actions: ["statistics", "orders"]
           }

    assert DashboardLayout.get(first.id) == canonical
    assert DashboardLayout.get(second.id) == DashboardLayout.default()

    assert {:ok, ^canonical} = DashboardLayout.save(first.id, canonical)
    assert {:ok, default} = DashboardLayout.reset(first.id)
    assert default == DashboardLayout.default()
    assert DashboardLayout.get(first.id) == default
  end

  test "rejects unknown, repeated, or out-of-bounds values without replacing saved data" do
    staff = insert(:staff)
    assert {:ok, saved} = DashboardLayout.save(staff.id, DashboardLayout.default())

    invalid = [
      %{widgets: [%{id: "revenue", x: 10, y: 0, w: 3, h: 2}], actions: []},
      %{widgets: [%{id: "made_up", x: 0, y: 0, w: 3, h: 2}], actions: []},
      %{widgets: List.duplicate(%{id: "revenue", x: 0, y: 0, w: 3, h: 2}, 2), actions: []},
      %{widgets: [], actions: ["orders", "orders"]},
      %{widgets: [], actions: ["arbitrary"]}
    ]

    Enum.each(invalid, fn params ->
      assert {:error, _} = DashboardLayout.save(staff.id, params)
      assert DashboardLayout.get(staff.id) == saved
    end)
  end
end
