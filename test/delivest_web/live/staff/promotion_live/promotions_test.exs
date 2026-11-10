defmodule DelivestWeb.Staff.PromotionLive.PromotionsTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Promo.{PromoCode, Promotion}
  alias Delivest.Repo

  setup %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    branch = insert(:branch)
    insert_branch_product(branch.id, slug: "cola", name: "Cola", price: 90)

    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    %{conn: conn, branch: branch}
  end

  test "creation starts with a scenario chooser and full form has no quick start", %{
    conn: conn,
    branch: branch
  } do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions")

    lv |> element("#new-promotion", "Create promotion") |> render_click()
    assert_patch(lv, ~p"/staff/b/#{branch}/promotions/new")
    assert has_element?(lv, "#promotion-scenarios #scenario-product")
    assert has_element?(lv, "#promotion-scenarios #scenario-first-order")
    assert has_element?(lv, "#promotion-scenarios #scenario-full")

    lv |> element("#scenario-full") |> render_click()
    assert_patch(lv, ~p"/staff/b/#{branch}/promotions/new/full")

    assert has_element?(lv, "#promotion-editor #promotion-form")
    refute has_element?(lv, "#promotions")
    refute has_element?(lv, "#promotion-templates")
    assert has_element?(lv, "#promotion-kind input[value=public_code][checked]")

    lv |> form("#promotion-form", promotion: %{kind: "automatic"}) |> render_change()
    assert has_element?(lv, "#promotion-kind input[value=automatic][checked]")
    refute has_element?(lv, "#promotion_code")
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

    assert has_element?(lv, "#new-promotion", "Создать акцию")
    lv |> element("#new-promotion") |> render_click()
    assert has_element?(lv, "#promotion-scenarios", "Выберите сценарий акции")
    assert has_element?(lv, "#scenario-first-order", "Первый заказ")

    assert has_element?(
             lv,
             "#scenario-first-order",
             "Выберите награду за первый заказ клиента на сайте или в приложении в этом филиале."
           )
  end

  test "creates a public promo code with the rules constructor", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/new/full")

    lv |> element("#add-condition button[phx-value-type=subtotal]") |> render_click()
    lv |> element("#effect-0 button[phx-click=remove_effect]") |> render_click()
    lv |> element("#add-effect button[phx-value-type=gift]") |> render_click()

    html =
      lv
      |> form("#promotion-form",
        promotion: %{kind: "public_code"},
        builder: %{
          conditions: %{"0" => %{op: ">=", value: "1000"}},
          effects: %{"0" => %{product: "cola", count: "1"}}
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
        effects: %{"0" => %{product: "cola", count: "1"}}
      }
    )
    |> render_submit()

    assert %Promotion{kind: :public_code} = promotion = Repo.get_by!(Promotion, name: "Summer")
    assert promotion.rules == "when subtotal >= 1000\nthen gift \"cola\" x1"
    assert promotion.branch_id == branch.id
    assert Repo.get_by!(PromoCode, promotion_id: promotion.id).code == "SUMMER26"
    assert has_element?(lv, "#promotion-#{promotion.id}")
  end

  test "first-order scenario saves a gift with fixed safe defaults", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/new/first-order")

    assert has_element?(lv, "#first-order-kind input[value=automatic][checked]")
    refute has_element?(lv, ~s([name="promotion[name]"]))
    refute has_element?(lv, ~s([name="promotion[per_client_limit]"]))
    refute has_element?(lv, ~s([name="promotion[combinable]"]))
    assert has_element?(lv, "#effect-0")

    for type <- ~w(percent amount gift gift_any price) do
      assert has_element?(lv, "#add-effect button[phx-value-type=#{type}]")
    end

    lv |> element("#effect-0 button[phx-click=remove_effect]") |> render_click()
    lv |> element("#add-effect button[phx-value-type=gift]") |> render_click()

    lv
    |> form("#promotion-form", builder: %{effects: %{"0" => %{product: "cola", count: "1"}}})
    |> render_change()

    assert has_element?(lv, "#rules-preview")
    refute has_element?(lv, "#rules-preview details")

    lv
    |> element("#promotion-form")
    |> render_submit(%{
      "promotion" => %{
        "kind" => "automatic",
        "name" => "Forged name",
        "per_client_limit" => "9",
        "combinable" => "true",
        "enabled" => "false",
        "priority" => "999",
        "starts_at" => "2028-01-01T00:00",
        "ends_at" => "2028-02-01T00:00"
      },
      "builder" => %{
        "match" => "any",
        "conditions" => %{"0" => %{"type" => "subtotal", "value" => "5000"}},
        "effects" => %{"0" => %{"type" => "gift", "product" => "cola", "count" => "1"}}
      }
    })

    assert %Promotion{
             rules: ~s(when first_order\nthen gift "cola" x1),
             name: "First order offer",
             per_client_limit: 1,
             combinable: false,
             enabled: true,
             priority: 100,
             starts_at: nil,
             ends_at: nil
           } = Repo.get_by!(Promotion, branch_id: branch.id)
  end

  test "first-order scenario supports public and personal code delivery", %{
    conn: conn,
    branch: branch
  } do
    for kind <- ~w(public_code personal_code) do
      {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/new/first-order")

      lv |> form("#promotion-form", promotion: %{kind: kind}) |> render_change()
      if kind == "public_code", do: assert(has_element?(lv, "#promotion_code"))

      lv
      |> form("#promotion-form",
        promotion: %{kind: kind},
        builder: %{effects: %{"0" => %{type: "percent", value: "10", target: "cart"}}}
      )
      |> render_submit()

      promotion =
        Repo.get_by!(Promotion, branch_id: branch.id, kind: String.to_existing_atom(kind))

      assert promotion.rules == "when first_order\nthen discount 10%"
      assert promotion.per_client_limit == 1
      refute promotion.combinable

      if kind == "public_code" do
        assert %PromoCode{code: "FIRST" <> _} =
                 Repo.get_by!(PromoCode, promotion_id: promotion.id)
      else
        refute Repo.get_by(PromoCode, promotion_id: promotion.id)
      end
    end
  end

  test "puts a product on sale from the quick form", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/sale")

    lv
    |> form("#sale-form", sale: %{add: "cola", mode: "percent", value: "20"})
    |> render_change()

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

  test "rejects a sale price that is not lower", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/sale")

    lv
    |> form("#sale-form", sale: %{add: "cola", mode: "price", value: "150"})
    |> render_submit()

    assert has_element?(lv, "#sale-error")
    refute Repo.get_by(Promotion, kind: :automatic)
  end

  test "highlights incomplete constructor rows", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/new/full")

    lv
    |> form("#promotion-form", promotion: %{name: "Empty"})
    |> render_submit()

    assert has_element?(lv, "#builder-errors")
    assert has_element?(lv, "#effect-0 .border-error")
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

  test "shows DSL errors and unknown products in text mode", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/promotions/new/full")

    lv |> element("button[phx-click=text_mode]") |> render_click()

    html =
      lv
      |> form("#promotion-form", promotion: %{name: "Bad", rules: "then gift \"ghost\""})
      |> render_submit()

    assert html =~ "ghost"
    refute Repo.get_by(Promotion, name: "Bad")

    html =
      lv
      |> form("#promotion-form", promotion: %{name: "Bad", rules: "when then"})
      |> render_change()

    assert html =~ "1:6"
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
end
