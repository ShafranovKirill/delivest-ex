defmodule DelivestWeb.PageControllerTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  test "guests are invited to sign in", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Sign in to the control panel"
    assert html =~ ~s(href="/staff/auth/login")
  end

  test "signed in staff go straight to the control panel", %{conn: conn} do
    staff = insert(:staff, name: "Ivan", role: insert(:role, permissions: ["admin"]))

    html =
      conn
      |> init_test_session(%{"staff_id" => staff.id})
      |> get(~p"/")
      |> html_response(200)

    assert html =~ "Open control panel"
    assert html =~ "You are signed in as Ivan"
    assert html =~ ~s(href="/staff")
  end
end
