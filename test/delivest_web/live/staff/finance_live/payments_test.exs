defmodule DelivestWeb.Staff.FinanceLive.PaymentsTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Integrations.{Health, Yookassa}
  alias Delivest.Payments

  setup %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["finance.read", "finance.update"]))
    insert(:staff_branch, staff: staff, branch: branch)

    %{
      conn: init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id}),
      branch: branch
    }
  end

  test "the nav has the finance group with payment and receipts", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/finance/payments")
    assert has_element?(lv, ~s(a[href="/staff/b/#{branch.slug}/finance/payments"]))
  end

  test "online payment is locked until YooKassa passes the check", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/finance/payments")
    assert has_element?(lv, "#online-unavailable")
    assert has_element?(lv, ~s(input[name="payments[online]"][disabled]))
  end

  test "saves the methods of the branch", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/finance/payments")

    lv |> form("#payments-form", payments: %{cash: "false"}) |> render_submit()

    assert Payments.settings(branch).cash == false
    assert Payments.enabled_methods(branch) == [:card_offline]
  end

  test "at least one method stays on", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/finance/payments")

    form = form(lv, "#payments-form", payments: %{cash: "false", card_offline: "false"})

    assert render_change(form) =~
             Gettext.gettext(DelivestWeb.Gettext, "Enable at least one payment method")

    render_submit(form)
    assert Payments.settings(branch).cash
  end

  test "online and the no-call option are available once YooKassa is ready", %{
    conn: conn,
    branch: branch
  } do
    Delivest.Repo.insert!(%Yookassa.Settings{shop_id: "506751", secret_key: "k"})

    Delivest.Repo.insert!(%Health.Status{
      provider: "yookassa",
      status: :ok,
      checked_at: DateTime.utc_now()
    })

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/finance/payments")
    refute has_element?(lv, "#online-unavailable")

    lv |> form("#payments-form", payments: %{online: "true"}) |> render_change()

    lv
    |> form("#payments-form", payments: %{online: "true", skip_confirmation_call: "true"})
    |> render_submit()

    assert %{online: true, skip_confirmation_call: true} = Payments.settings(branch)
    assert :online in Payments.enabled_methods(branch)
  end

  test "a role without finance.read is turned away", %{conn: conn, branch: branch} do
    staff = insert(:staff, role: insert(:role, permissions: ["orders.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    assert {:error, {:redirect, _}} = live(conn, ~p"/staff/b/#{branch}/finance/payments")
  end
end
