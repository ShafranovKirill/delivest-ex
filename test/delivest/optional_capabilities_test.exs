defmodule Delivest.OptionalCapabilitiesTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory

  alias Delivest.{Features, Loyalty, Net, Promo}
  alias Delivest.Features.Gate
  alias Delivest.Integrations.StaffAccess

  test "new branches receive explicit gates and disabling does not remove core pricing" do
    branch = insert(:branch)
    scope = {:branch, branch.id}

    for feature <- ~w(product_import event_log analytics_basic stocks promotions loyalty kitchen) do
      assert %Gate{enabled: true} =
               Repo.get_by(Gate, feature: feature, scope_key: "branch:" <> branch.id)
    end

    product = insert_branch_product(branch.id, slug: "pizza", name: "Pizza", price: 50_000)
    insert_promotion(branch.id, rules: ~s(then price "pizza" 450))

    item = %{
      product_id: product.id,
      name: product.name,
      image_url: nil,
      price: product.price,
      quantity: 1
    }

    assert Promo.price([item], %{branch_id: branch.id}).total == 45_000

    assert [%{products: [%{old_price: 50_000, price: 45_000}]}] =
             Promo.overlay_menu([%{products: [product]}], branch.id)

    assert {:ok, _} = Features.configure("promotions", scope, false, actor: "test")
    assert Promo.price([item], %{branch_id: branch.id}).total == 50_000
    assert Promo.list_running_promotions(branch.id) == []

    assert [%{products: [%{old_price: nil, price: 50_000}]}] =
             Promo.overlay_menu([%{products: [product]}], branch.id)

    assert {:ok, _} = Features.configure("promotions", scope, true, actor: "test")
    assert Promo.price([item], %{branch_id: branch.id}).total == 45_000
  end

  test "optional add-ons disappear while branch order capabilities remain enabled" do
    branch = insert(:branch)
    scope = {:branch, branch.id}

    for feature <- ~w(product_import event_log analytics_basic stocks promotions loyalty kitchen) do
      assert {:ok, _} = Features.configure(feature, scope, false, actor: "test")
      refute Features.enabled?(feature, scope)
    end

    assert Net.list_stocks_for_branch(branch.id) == []
    refute Loyalty.enabled?(branch.id)
  end

  test "legacy zvonok switch cannot disable core phone verification" do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.insert_all(
      Gate,
      [
        %{
          feature: "integration_zvonok",
          scope_key: "franchise",
          enabled: false,
          generation: 1,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: [set: [enabled: false]],
      conflict_target: [:feature, :scope_key]
    )

    assert StaffAccess.allowed?(:zvonok)
    refute StaffAccess.permission?("integration_zvonok")
  end
end
