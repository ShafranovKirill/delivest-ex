defmodule Delivest.Oms.ComboAvailabilityTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Integrations.Frontpad

  alias Delivest.Net.{
    Category,
    Modifier,
    ModifierGroup,
    Product,
    ProductModifierGroup,
    PublicOffers,
    Stops
  }

  alias Delivest.Oms.{Carts, Orders}
  alias Delivest.Oms.Orders.StopGuard
  alias Delivest.Promo.{Line, Result}
  alias DelivestWeb.Client.Cart.CartJSON

  setup do
    branch = insert(:branch, is_active: true)
    category = insert(:category)
    component_category = insert(:category)
    Delivest.Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id)

    Delivest.Relations.create_relation(
      Repo,
      "Branch",
      branch.id,
      "Category",
      component_category.id
    )

    component = insert_branch_product(branch.id, name: "Burger", category: component_category)
    combo = insert_branch_product(branch.id, name: "Lunch", is_combo: true, category: category)
    group = Repo.insert!(%ModifierGroup{name: "Main", min: 1, max: 1})

    choice =
      Repo.insert!(%Modifier{
        group_id: group.id,
        name: "Burger",
        component_product_id: component.id,
        max_quantity: 1
      })

    Repo.insert!(%ProductModifierGroup{product_id: combo.id, group_id: group.id, position: 0})
    {:ok, cart} = Carts.create_cart(%{session_id: "combo-availability", branch_id: branch.id})

    %{
      branch: branch,
      component: component,
      component_category: component_category,
      combo: combo,
      choice: choice,
      cart: cart
    }
  end

  test "a required component must be explicitly selected", ctx do
    assert {:error, _} = Carts.add_item(ctx.cart.id, ctx.combo.id)
    assert {:ok, _, view} = Carts.add_item(ctx.cart.id, ctx.combo.id, 1, [ctx.choice.id])
    assert [item] = view.items
    refute Map.get(item, :unavailable, false)
  end

  test "an unavailable component blocks an existing cart and final order line", ctx do
    assert {:ok, _, _} = Carts.add_item(ctx.cart.id, ctx.combo.id, 1, [ctx.choice.id])
    ctx.component |> Product.changeset(%{is_active: false}) |> Repo.update!()

    view = Carts.get_cart_by_id(ctx.cart.id, force: true)
    assert [%{unavailable: true}] = view.items

    line = %Line{product_id: ctx.combo.id, modifiers: [%{id: ctx.choice.id}]}

    assert {:error, :product_unavailable} =
             StopGuard.check(ctx.branch.id, %Result{lines: [line]})
  end

  test "a generated gift cannot bypass required combo choices", ctx do
    line = %Line{product_id: ctx.combo.id, gift: true, modifiers: []}

    assert {:error, :product_unavailable} =
             StopGuard.check(ctx.branch.id, %Result{lines: [line]})
  end

  test "an inactive component category blocks selection", ctx do
    ctx.component_category |> Category.changeset(%{is_active: false}) |> Repo.update!()
    assert {:error, _} = Carts.add_item(ctx.cart.id, ctx.combo.id, 1, [ctx.choice.id])

    assert {:ok, categories} = PublicOffers.menu_fresh(ctx.branch.id)
    offer = categories |> Enum.flat_map(& &1.products) |> Enum.find(&(&1.id == ctx.combo.id))
    assert [%{modifiers: [%{stopped: true}]}] = offer.modifier_groups
    refute PublicOffers.purchasable?(offer)
  end

  test "a stopped component blocks menu selection and checkout of a stale cart", ctx do
    assert {:ok, _, _} = Carts.add_item(ctx.cart.id, ctx.combo.id, 1, [ctx.choice.id])
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    assert {:ok, _} = Stops.stop(staff, ctx.branch.id, ctx.component, :until_resumed)

    assert {:ok, categories} = PublicOffers.menu_fresh(ctx.branch.id)
    offer = categories |> Enum.flat_map(& &1.products) |> Enum.find(&(&1.id == ctx.combo.id))
    assert [%{modifiers: [%{stopped: true}]}] = offer.modifier_groups
    refute PublicOffers.purchasable?(offer)

    assert {:error, _} = Carts.add_item(ctx.cart.id, ctx.combo.id, 1, [ctx.choice.id])

    assert {:error, _, :product_unavailable} =
             Orders.create_order(%{
               "cart_id" => ctx.cart.id,
               "branch_id" => ctx.branch.id,
               "fulfillment_type" => "pickup",
               "payment_method" => "cash"
             })
  end

  test "a CRM app route hides the combo and marks an existing cart line", ctx do
    assert {:ok, _, _} = Carts.add_item(ctx.cart.id, ctx.combo.id, 1, [ctx.choice.id])

    Repo.insert!(%BranchInfo{
      branch_id: ctx.branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        sources: ["app"],
        frontpad: %Frontpad.Settings{api_key: "test", affiliate: "3"}
      }
    })

    Cachex.del(:branch_cache, ctx.branch.id)

    assert {:ok, categories} = PublicOffers.menu_fresh(ctx.branch.id)
    refute Enum.any?(Enum.flat_map(categories, & &1.products), &(&1.id == ctx.combo.id))
    assert {:error, :not_found} = PublicOffers.product(ctx.branch.id, ctx.combo.id)

    cart = Carts.get_cart_by_id(ctx.cart.id, force: true)

    assert %{data: %{items: [%{unavailable_reason: :combo_requires_delivest}]}} =
             CartJSON.show(%{cart: cart})

    line = %Line{product_id: ctx.combo.id, gift: true, modifiers: [%{id: ctx.choice.id}]}

    assert {:error, :combo_requires_delivest} =
             StopGuard.check(ctx.branch.id, %Result{lines: [line]}, crm: %{provider: :frontpad})

    attrs = %{
      "cart_id" => ctx.cart.id,
      "branch_id" => ctx.branch.id,
      "fulfillment_type" => "pickup",
      "payment_method" => "cash"
    }

    assert {:error, _, :combo_requires_delivest} = Orders.create_order(attrs)

    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    assert {:ok, _} = Stops.stop(staff, ctx.branch.id, ctx.component, :until_resumed)

    assert {:error, _, :combo_requires_delivest} = Orders.create_order(attrs)
  end
end
