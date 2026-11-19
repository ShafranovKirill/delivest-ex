defmodule DelivestWeb.Staff.PromotionLive.PromotionsTest do
  use DelivestWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Promo.{PromoCode, Promotion}
  alias Delivest.Repo

  setup %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    branch = insert(:branch)
    product = insert_branch_product(branch.id, slug: "cola", name: "Cola", price: 90)

    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    %{conn: conn, branch: branch, product: product}
  end

  test "creation starts with a scenario chooser and full form has no quick start", %{
    conn: conn,
    branch: branch
  } do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions")

    assert has_element?(lv, "#staff-page-header-actions #new-promotion")
    render_patch(lv, ~p"/staff/b/#{branch}/promotions/new")
    assert_patch(lv, ~p"/staff/b/#{branch}/promotions/new")
    assert has_element?(lv, "#promotion-scenarios #scenario-product")
    assert has_element?(lv, "#promotion-scenarios #scenario-gift-threshold")
    assert has_element?(lv, "#promotion-scenarios #scenario-bundle")
    assert has_element?(lv, "#promotion-scenarios #scenario-pickup")
    refute has_element?(lv, "#promotion-scenarios #scenario-automatic")
    refute has_element?(lv, "#promotion-scenarios #scenario-first-order")
    assert has_element?(lv, "#promotion-scenarios #scenario-full")
    assert has_element?(lv, "#promotion-scenarios .grid > a:first-child#scenario-full")
    assert has_element?(lv, "#promotion-scenarios .grid > a:nth-child(2)#scenario-product")
    assert has_element?(lv, "#promotion-scenarios .grid > a:nth-child(3)#scenario-gift-threshold")
    assert has_element?(lv, "#promotion-scenarios .grid > a:nth-child(4)#scenario-bundle")
    assert has_element?(lv, "#promotion-scenarios .grid > a:last-child#scenario-pickup")

    assert lv
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("#promotion-scenarios .grid > a")
           |> LazyHTML.to_tree()
           |> length() == 5

    lv |> element("#scenario-full") |> render_click()
    assert_patch(lv, ~p"/staff/b/#{branch}/promotions/new/full")

    assert has_element?(lv, "#promotion-editor #promotion-form")
    refute has_element?(lv, "#promotions")
    refute has_element?(lv, "#promotion-templates")
    assert has_element?(lv, "#promotion-kind input[value=public_code][checked]")
    assert has_element?(lv, "#promotion-kind input[value=automatic]")
    refute has_element?(lv, "#effect-0")
    refute has_element?(lv, "#condition-0")
    refute has_element?(lv, "button[phx-click=text_mode]")
    refute has_element?(lv, "#rules-code")
  end

  test "direct creation routes require create permission", %{branch: branch} do
    staff = insert(:staff, role: insert(:role, permissions: ["promotions.read"]))
    insert(:staff_branch, staff: staff, branch: branch)

    conn =
      Phoenix.ConnTest.build_conn()
      |> init_test_session(%{"staff_id" => staff.id, "active_branch_id" => branch.id})

    for path <- ["new", "new/full", "new/first-order", "sale"] do
      assert {:error, {:live_redirect, %{to: target}}} =
               live(conn, "/staff/b/#{branch.slug}/promotions/#{path}")

      assert target == ~p"/staff/b/#{branch}/promotions"
    end
  end

  test "chooser uses reviewed Russian labels", %{conn: conn, branch: branch} do
    conn = init_test_session(conn, %{"locale" => "ru"})
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions")

    assert has_element?(lv, "#staff-page-header-actions #new-promotion", "Создать")

    render_patch(lv, ~p"/staff/b/#{branch}/promotions/new")
    assert has_element?(lv, "main #staff-page-header h1", "Что создать?")
    assert has_element?(lv, "#scenario-full", "Создать промокод")
    assert has_element?(lv, "#scenario-product", "Скидка на товар")
    assert has_element?(lv, "#scenario-gift-threshold", "Подарок от суммы")
    assert has_element?(lv, "#scenario-bundle", "Набор дешевле")
    assert has_element?(lv, "#scenario-pickup", "Промокод на самовывоз")
    refute has_element?(lv, "#scenario-automatic")
    refute has_element?(lv, "#scenario-first-order")
  end

  test "creates a public promo code with the rules constructor", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/new/full")

    lv |> element("#add-condition button[phx-value-type=subtotal]") |> render_click()
    lv |> element("#add-effect button[phx-value-type=gift]") |> render_click()
    lv |> element("#builder-e0-picker") |> render_click()
    lv |> form("#promotion-product-picker-search", search: "Cola") |> render_change()

    lv
    |> element("#promotion-product-picker-product-#{product.id} input[phx-click=toggle]")
    |> render_click()

    lv |> element("#promotion-product-picker button[phx-click=save]") |> render_click()

    html =
      lv
      |> form("#promotion-form",
        promotion: %{kind: "public_code"},
        builder: %{
          conditions: %{"0" => %{op: ">=", value: "1000"}},
          effects: %{"0" => %{count: "1"}}
        }
      )
      |> render_change()

    assert html =~ "Cola"
    assert has_element?(lv, "#rules-preview")

    lv
    |> form("#promotion-form",
      promotion: %{name: "Summer", kind: "public_code", code: "summer26"},
      builder: %{
        conditions: %{"0" => %{op: ">=", value: "1000"}},
        effects: %{"0" => %{count: "1"}}
      }
    )
    |> render_submit()

    assert %Promotion{kind: :public_code} = promotion = Repo.get_by!(Promotion, name: "Summer")
    assert promotion.rules == "when subtotal >= 1000\nthen gift \"cola\" x1"
    assert promotion.branch_id == branch.id
    assert Repo.get_by!(PromoCode, promotion_id: promotion.id).code == "SUMMER26"
    assert has_element?(lv, "#promotion-#{promotion.id}")
  end

  test "legacy first-order URL opens an empty promo form", %{conn: conn, branch: branch} do
    assert {:error, {:live_redirect, %{to: path}}} =
             live(conn, ~p"/staff/b/#{branch}/promotions/new/first-order")

    assert path == ~p"/staff/b/#{branch}/promotions/new/full"
    {:ok, lv, _html} = live(conn, path)
    refute has_element?(lv, "#condition-0")
    refute has_element?(lv, "#effect-0")
  end

  test "automatic promotion can manually require a first order", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/new/full?kind=automatic")
    assert has_element?(lv, "#promotion-kind input[value=automatic][checked]")
    refute has_element?(lv, "#promotion_code")

    lv |> element("#add-condition button[phx-value-type=first_order]") |> render_click()
    lv |> element("#add-effect button[phx-value-type=percent]") |> render_click()

    lv
    |> form("#promotion-form",
      promotion: %{name: "First order", per_client_limit: "1"},
      builder: %{effects: %{"0" => %{value: "10"}}}
    )
    |> render_submit()

    assert %Promotion{
             kind: :automatic,
             rules: "when first_order\nthen discount 10%",
             per_client_limit: 1
           } =
             Repo.get_by!(Promotion, name: "First order")
  end

  test "normal full form switches between automatic and public code", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/new/full")
    lv |> element("#add-effect button[phx-value-type=percent]") |> render_click()
    lv |> form("#promotion-form", promotion: %{code: "SAVE10"}) |> render_change()
    lv |> form("#promotion-form", promotion: %{kind: "automatic"}) |> render_change()
    assert has_element?(lv, "#promotion-kind input[value=automatic][checked]")
    refute has_element?(lv, "#promotion_code")

    lv
    |> form("#promotion-form", builder: %{effects: %{"0" => %{value: "10"}}})
    |> render_change()

    lv |> form("#promotion-form", promotion: %{kind: "public_code"}) |> render_change()
    assert has_element?(lv, "#promotion-kind input[value=public_code][checked]")
    assert has_element?(lv, "#promotion_code[value=SAVE10]")
    assert has_element?(lv, "#builder-e0-value[value='10']")

    lv
    |> form("#promotion-form",
      promotion: %{kind: "automatic", name: "Automatic ten"},
      builder: %{effects: %{"0" => %{value: "10"}}}
    )
    |> render_submit()

    assert %Promotion{kind: :automatic, rules: "then discount 10%"} =
             Repo.get_by!(Promotion, name: "Automatic ten")
  end

  test "gift above a cart total requires all values and saves its rules", %{
    conn: conn, branch: branch, product: product
  } do
    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/promotions/new/full?template=gift_threshold")
    assert has_element?(lv, "#promotion-kind input[value=public_code][checked]")
    assert has_element?(lv, "#promotion-kind input[value=automatic]")
    assert has_element?(lv, "#builder-c0-value[value='']")
    assert has_element?(lv, "#builder-e0-count[value='']")

    lv |> form("#promotion-form", promotion: %{name: "Gift", code: "GIFT"}) |> render_submit()
    refute Repo.get_by(Promotion, name: "Gift")
    assert has_element?(lv, "#condition-0 .text-error")
    assert has_element?(lv, "#effect-0 .text-error")

    choose_product(lv, "#builder-e0-picker", product)

    lv
    |> form("#promotion-form",
      promotion: %{name: "Gift", code: "GIFT"},
      builder: %{conditions: %{"0" => %{value: "1000"}}, effects: %{"0" => %{count: "1"}}}
    )
    |> render_submit()

    assert Repo.get_by!(Promotion, name: "Gift").rules ==
             ~s(when subtotal >= 1000\nthen gift "cola" x1)
  end

  test "bundle requires distinct products and discounts the order", %{
    conn: conn, branch: branch, product: cola
  } do
    tea = insert_branch_product(branch.id, slug: "tea", name: "Tea", price: 70)
    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/promotions/new/full?template=bundle")
    assert has_element?(lv, "#condition-0")
    assert has_element?(lv, "#condition-1")
    assert has_element?(lv, "#builder-e0-value[value='']")
    assert has_element?(lv, "#promotion-kind input[value=personal_code]")

    lv |> form("#promotion-form", promotion: %{name: "Bundle", code: "BUNDLE"}) |> render_submit()
    refute Repo.get_by(Promotion, name: "Bundle")

    choose_product(lv, "#builder-c0-picker", cola)
    choose_product(lv, "#builder-c1-picker", cola)
    lv |> element("#add-condition button[phx-value-type=subtotal]") |> render_click()

    bundle_form = [
      promotion: %{name: "Bundle", code: "BUNDLE"},
      builder: %{
        conditions: %{"2" => %{value: "500"}},
        effects: %{"0" => %{value: "100"}}
      }
    ]

    lv |> form("#promotion-form", bundle_form) |> render_submit()
    assert has_element?(lv, "#condition-1 .text-error", "Выберите другой товар")
    refute Repo.get_by(Promotion, name: "Bundle")

    lv |> element("#condition-2 button[phx-click=remove_condition]") |> render_click()
    choose_product(lv, "#builder-c1-picker", tea)

    lv
    |> form("#promotion-form",
      promotion: %{name: "Bundle", code: "BUNDLE"},
      builder: %{effects: %{"0" => %{value: "100"}}}
    )
    |> render_submit()
    assert Repo.get_by!(Promotion, name: "Bundle").rules ==
             ~s(when has "cola" x1\n  and has "tea" x1\nthen discount 100 rub)
  end

  test "pickup template keeps its condition through validation and saves", %{
    conn: conn, branch: branch
  } do
    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/promotions/new/full?template=pickup")
    assert has_element?(lv, "#builder-c0-pickup[checked]")
    assert has_element?(lv, "#builder-e0-value[value='']")
    assert has_element?(lv, "#promotion-kind input[value=automatic]")

    lv |> form("#promotion-form", promotion: %{name: "Pickup", code: "PICKUP"}) |> render_submit()
    refute Repo.get_by(Promotion, name: "Pickup")
    assert has_element?(lv, "#builder-c0-pickup[checked]")

    lv
    |> form("#promotion-form",
      promotion: %{name: "Pickup", code: "PICKUP"},
      builder: %{effects: %{"0" => %{value: "10"}}}
    )
    |> render_submit()

    assert Repo.get_by!(Promotion, name: "Pickup").rules ==
             "when fulfillment in (pickup)\nthen discount 10%"
  end

  test "switching templates resets draft rules while ordinary validation keeps them", %{
    conn: conn, branch: branch
  } do
    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/promotions/new/full?template=gift_threshold")

    lv
    |> form("#promotion-form", builder: %{conditions: %{"0" => %{value: "1500"}}})
    |> render_change()

    assert has_element?(lv, "#builder-c0-value[value='1500']")
    render_patch(lv, ~p"/staff/b/#{branch}/promotions/new/full?template=pickup")
    assert has_element?(lv, "#builder-c0-pickup[checked]")
    refute has_element?(lv, "#builder-c0-value")

    render_patch(lv, ~p"/staff/b/#{branch}/promotions/new/full")
    refute has_element?(lv, "#condition-0")
    refute has_element?(lv, "#effect-0")
  end

  test "personal promo codes can manually require a first order", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/new/full")
    lv |> element("#add-condition button[phx-value-type=first_order]") |> render_click()
    lv |> element("#add-effect button[phx-value-type=percent]") |> render_click()

    lv
    |> form("#promotion-form",
      promotion: %{name: "Personal first", kind: "personal_code"},
      builder: %{effects: %{"0" => %{value: "10"}}}
    )
    |> render_submit()

    assert %Promotion{kind: :personal_code, rules: "when first_order\nthen discount 10%"} =
             Repo.get_by!(Promotion, name: "Personal first")
  end

  test "puts a product on sale from the quick form", %{
    conn: conn,
    branch: branch,
    product: product
  } do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/sale")

    lv |> element("#sale-open-product-picker") |> render_click()
    lv |> form("#sale-product-picker-search", search: "Cola") |> render_change()

    lv
    |> element("#sale-product-picker-product-#{product.id} input[phx-click=toggle]")
    |> render_click()

    lv |> element("#sale-product-picker button[phx-click=save]") |> render_click()
    lv |> form("#sale-form", sale: %{mode: "percent", value: "20"}) |> render_change()

    assert has_element?(lv, "#sale-products", "Cola")
    assert has_element?(lv, "#sale-preview", "72 ₽")

    lv
    |> form("#sale-form", sale: %{products: ["cola"], mode: "percent", value: "20"})
    |> render_submit()

    assert %Promotion{kind: :automatic, combinable: true} =
             promotion = Repo.get_by!(Promotion, branch_id: branch.id)

    assert promotion.rules == "then discount 20% on \"cola\""
    assert promotion.name =~ "Cola"
  end

  test "product picker keeps rule counts and selected targets through later validation", %{
    conn: conn,
    branch: branch,
    product: first
  } do
    second = insert_branch_product(branch.id, slug: "tea", name: "Tea", price: 70)
    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/promotions/new/full")
    lv |> element("#add-condition button[phx-value-type=has_any]") |> render_click()
    lv |> element("#add-effect button[phx-value-type=percent]") |> render_click()

    lv
    |> form("#promotion-form",
      builder: %{
        conditions: %{"0" => %{count: "2"}},
        effects: %{"0" => %{value: "10", target: "products"}}
      }
    )
    |> render_change()

    lv |> element("#condition-0-picker") |> render_click()
    lv |> form("#promotion-product-picker-search", search: "Cola") |> render_change()

    lv
    |> element("#promotion-product-picker-product-#{first.id} input[phx-click=toggle]")
    |> render_click()

    lv
    |> element("#promotion-product-picker button.btn-outline[phx-click=cancel]")
    |> render_click()

    refute has_element?(lv, ~s(#condition-0 input[value="cola"]))

    lv |> element("#condition-0-picker") |> render_click()
    lv |> form("#promotion-product-picker-search", search: "") |> render_change()
    lv |> element("#promotion-product-picker input[phx-click=category_all]") |> render_click()
    lv |> element("#promotion-product-picker button[phx-click=save]") |> render_click()

    assert has_element?(
             lv,
             ~s(#condition-0 input[name="builder[conditions][0][count]"][value="2"])
           )

    assert has_element?(lv, ~s(#condition-0 input[value="cola"]))
    assert has_element?(lv, ~s(#condition-0 input[value="tea"]))

    lv |> form("#promotion-form", promotion: %{name: "Combo"}) |> render_change()
    assert has_element?(lv, ~s(#condition-0 input[value="cola"]))
    assert has_element?(lv, ~s(#condition-0 input[value="tea"]))

    assert has_element?(
             lv,
             ~s(#condition-0 input[name="builder[conditions][0][count]"][value="2"])
           )

    assert has_element?(lv, ~s(#effect-0 input[name="builder[effects][0][value]"][value="10"]))
    assert first.id != second.id
  end

  test "product discount offers code kinds and ignores forged advanced fields", %{
    conn: conn,
    branch: branch
  } do
    for kind <- ~w(public_code personal_code) do
      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/sale")
      assert has_element?(lv, "#sale-kind input[value=#{kind}]")

      lv
      |> element("#sale-form")
      |> render_submit(%{
        "promotion" => %{
          "kind" => kind,
          "name" => "Forged sale",
          "combinable" => "false",
          "enabled" => "false"
        },
        "sale" => %{"products" => ["cola"], "mode" => "percent", "value" => "20"}
      })

      promotion =
        Repo.get_by!(Promotion, branch_id: branch.id, kind: String.to_existing_atom(kind))

      assert promotion.name =~ "Cola"
      assert promotion.combinable
      assert promotion.enabled

      if kind == "public_code" do
        assert %PromoCode{code: "SALE" <> _} = Repo.get_by!(PromoCode, promotion_id: promotion.id)
      else
        refute Repo.get_by(PromoCode, promotion_id: promotion.id)
      end
    end
  end

  test "rejects a sale price that is not lower", %{conn: conn, branch: branch, product: product} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/sale")

    lv |> element("#sale-open-product-picker") |> render_click()
    lv |> form("#sale-product-picker-search", search: "Cola") |> render_change()

    lv
    |> element("#sale-product-picker-product-#{product.id} input[phx-click=toggle]")
    |> render_click()

    lv |> element("#sale-product-picker button[phx-click=save]") |> render_click()
    lv |> form("#sale-form", sale: %{mode: "price", value: "150"}) |> render_submit()

    assert has_element?(lv, "#sale-error")
    refute Repo.get_by(Promotion, kind: :automatic)
  end

  test "highlights incomplete constructor rows", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/new/full")

    lv
    |> form("#promotion-form", promotion: %{name: "Empty"})
    |> render_submit()

    assert has_element?(lv, "#promotion-reward-error.text-error")
    refute has_element?(lv, "#promotion-error-summary")
    refute has_element?(lv, "#builder-errors")
    refute Repo.get_by(Promotion, name: "Empty")
  end

  test "opens existing rules in the constructor", %{conn: conn, branch: branch} do
    promotion =
      insert_promotion(branch.id,
        rules: "when weekday in (sat, sun) and fulfillment in (pickup)\nthen discount 15% max 300"
      )

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/#{promotion.id}/edit")

    assert has_element?(lv, "#builder-c0-sat[checked]")
    assert has_element?(lv, "#builder-c1-pickup[checked]")
    assert has_element?(lv, "#builder-e0-cap[value='300']")
  end

  test "falls back to text for rules the constructor cannot show", %{conn: conn, branch: branch} do
    promotion = insert_promotion(branch.id, rules: "when not subtotal < 500 then discount 5%")

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/#{promotion.id}/edit")

    assert has_element?(lv, "textarea[name='promotion[rules]']")
    lv |> element("button[phx-click=builder_mode]") |> render_click()
    assert render(lv) =~ "too complex"
  end

  test "complex existing rules remain editable as text", %{conn: conn, branch: branch} do
    promotion = insert_promotion(branch.id, rules: "when not subtotal < 500 then discount 5%")
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/#{promotion.id}/edit")
    assert has_element?(lv, "textarea[name='promotion[rules]']")
    refute has_element?(lv, "button[phx-click=text_mode]")

    lv
    |> form("#promotion-form", promotion: %{name: "Renamed", rules: promotion.rules})
    |> render_submit()

    assert Repo.get!(Promotion, promotion.id).rules == promotion.rules
  end

  test "unused required fields stay quiet on change and show inline on submit", %{
    conn: conn,
    branch: branch
  } do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/new/full")

    lv
    |> element("#promotion-form")
    |> render_change(%{
      "promotion" => %{
        "name" => "",
        "code" => "",
        "_unused_name" => "",
        "_unused_code" => ""
      }
    })

    refute has_element?(lv, "#promotion_name + .text-error")
    refute has_element?(lv, "#promotion_code + .text-error")
    refute has_element?(lv, "#promotion-error-summary")

    lv |> form("#promotion-form", promotion: %{name: "", code: ""}) |> render_submit()
    assert has_element?(lv, "#promotion-reward-error.text-error")
    assert has_element?(lv, "#promotion_name")
    assert has_element?(lv, "#promotion_code")
  end

  test "issues a personal code by phone", %{conn: conn, branch: branch} do
    promotion = insert_promotion(branch.id, kind: :personal_code, rules: "then discount 100 rub")

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/#{promotion.id}/codes")

    lv
    |> form("#issue-code-form", issue: %{phone: "+79991234567", uses: "2"})
    |> render_submit()

    assert has_element?(lv, "#issued-code")

    assert %PromoCode{usage_limit: 2, client_id: client_id} =
             Repo.get_by!(PromoCode, promotion_id: promotion.id)

    assert client_id
  end

  defp choose_product(lv, picker, product) do
    lv |> element(picker) |> render_click()
    lv |> form("#promotion-product-picker-search", search: product.name) |> render_change()

    lv
    |> element("#promotion-product-picker-product-#{product.id} input[phx-click=toggle]")
    |> render_click()

    lv |> element("#promotion-product-picker button[phx-click=save]") |> render_click()
  end
end
