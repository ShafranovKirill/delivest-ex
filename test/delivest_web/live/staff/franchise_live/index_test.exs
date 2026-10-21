defmodule DelivestWeb.Staff.FranchiseLive.IndexTest do
  use DelivestWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Franchise

  setup %{conn: conn} do
    Cachex.clear(:franchise_cache)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    %{conn: init_test_session(conn, %{"staff_id" => staff.id})}
  end

  test "saves brand and seller details", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/staff/franchise")

    lv
    |> form("#franchise-settings-form", settings: %{primary_color: "#eeeeee"})
    |> render_change()

    assert has_element?(lv, "#franchise-color-warning")

    lv
    |> form("#franchise-settings-form",
      settings: %{name: "Pizza", primary_color: "#aa0000", inn: "7700000000"}
    )
    |> render_submit()

    assert %{name: "Pizza", primary_color: "#aa0000", inn: "7700000000"} =
             Franchise.get_settings()
  end

  test "edits and restores a document", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/staff/franchise/documents/terms")

    lv |> form("#document-form", document: %{body: "Новые правила"}) |> render_submit()

    assert %{custom: true, body: "Новые правила"} = Franchise.get_document(:terms)
    assert render(lv) =~ "Edited"

    {:ok, lv, _html} = live(conn, ~p"/staff/franchise/documents/terms")
    lv |> element("button[phx-click=reset]") |> render_click()

    assert %{custom: false} = Franchise.get_document(:terms)
  end

  test "is closed to non-admins", %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: ["branches.read"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    assert {:error, {:redirect, _}} = live(conn, ~p"/staff/franchise")
  end
end
