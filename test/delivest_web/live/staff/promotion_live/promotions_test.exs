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

  test "creates a public promo code with live rules preview", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/promotions/new")

    html =
      lv
      |> form("#promotion-form", promotion: %{rules: "when subtotal >= 1000 then gift \"cola\""})
      |> render_change()

    assert html =~ "Cola"
    assert has_element?(lv, "#rules-preview")

    lv |> form("#promotion-form", promotion: %{kind: "public_code"}) |> render_change()

    lv
    |> form("#promotion-form",
      promotion: %{
        name: "Summer",
        kind: "public_code",
        code: "summer26",
        rules: "when subtotal >= 1000 then gift \"cola\""
      }
    )
    |> render_submit()

    assert %Promotion{kind: :public_code} = promotion = Repo.get_by!(Promotion, name: "Summer")
    assert promotion.branch_id == branch.id
    assert Repo.get_by!(PromoCode, promotion_id: promotion.id).code == "SUMMER26"
    assert has_element?(lv, "#promotion-#{promotion.id}")
  end

  test "shows DSL errors and unknown products", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/staff/promotions/new")

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
