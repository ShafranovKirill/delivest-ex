defmodule Delivest.Integrations.Frontpad.FrontpadViewTest do
  use ExUnit.Case, async: true

  alias Delivest.Identity.Branch
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Frontpad.FrontpadView
  alias Delivest.Oms.{Order, OrderItem}

  test "maps cook_by to Frontpad datetime using the required format" do
    order = %Order{
      cook_by: ~N[2026-10-15 15:30:00],
      items: [%OrderItem{product_id: "product-1", quantity: 2}]
    }

    branch = %Branch{info: %BranchInfo{frontpad_api_key: "secret"}}
    products_map = %{"product-1" => %{external_id: "frontpad-product-1"}}

    assert {:ok, view} = FrontpadView.build(order, branch, products_map)

    assert {"datetime", "2026-10-15 15:30:00"} in FrontpadView.to_form_params(view)
  end

  test "omits Frontpad datetime when cook_by is empty" do
    order = %Order{items: []}
    branch = %Branch{info: %BranchInfo{frontpad_api_key: "secret"}}

    assert {:ok, view} = FrontpadView.build(order, branch, %{})

    refute Enum.any?(FrontpadView.to_form_params(view), fn {key, _value} -> key == "datetime" end)
  end
end
