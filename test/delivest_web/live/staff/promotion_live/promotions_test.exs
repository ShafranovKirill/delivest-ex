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

  test "creates a public promo code with the rules constructor", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/promotions/new")

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

  test "highlights incomplete constructor rows", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/staff/promotions/new")

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

    {:ok, lv, _html} = live(conn, ~p"/staff/promotions/#{promotion.id}/edit")

    assert has_element?(lv, "#builder-c0-sat[checked]")
    assert has_element?(lv, "#builder-c1-pickup[checked]")
    assert has_element?(lv, "#builder-e0-cap[value='300']")
  end

  test "falls back to text for rules the constructor cannot show", %{conn: conn, branch: branch} do
    promotion = insert_promotion(branch.id, rules: "when not subtotal < 500 then discount 5%")

    {:ok, lv, _html} = live(conn, ~p"/staff/promotions/#{promotion.id}/edit")

    assert has_element?(lv, "textarea[name='promotion[rules]']")
    lv |> element("button[phx-click=builder_mode]") |> render_click()
    assert render(lv) =~ "too complex"
  end

  test "shows DSL errors and unknown products in text mode", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/staff/promotions/new")

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

    {:ok, lv, _html} = live(conn, ~p"/staff/promotions/#{promotion.id}/codes")

    lv
    |> form("#issue-code-form", issue: %{phone: "+79991234567", uses: "2"})
    |> render_submit()

    assert has_element?(lv, "#issued-code")

    assert %PromoCode{usage_limit: 2, client_id: client_id} =
             Repo.get_by!(PromoCode, promotion_id: promotion.id)

    assert client_id
  end
end
