defmodule DelivestWeb.Staff.DiagnosticsLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  test "metrics appear inside the staff shell for authorized staff", %{conn: conn} do
    staff = insert(:staff, role: build(:role, permissions: ["logs.read"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, view, _html} = live(conn, ~p"/staff/diagnostics")

    assert has_element?(view, "#main-sidebar")
    assert has_element?(view, "#staff-page-header")
    assert has_element?(view, "#staff-metrics-frame[src='/staff/metrics']")

    conn = get(conn, ~p"/staff/metrics")
    assert redirected_to(conn) == ~p"/staff/metrics/home"
    conn = conn |> recycle() |> get(~p"/staff/metrics/home")
    assert conn.status == 200

    assert get_resp_header(conn, "content-security-policy") == [
             "base-uri 'self'; frame-ancestors 'self';"
           ]
  end

  test "staff without log permission cannot open the wrapper", %{conn: conn} do
    staff = insert(:staff, role: build(:role, permissions: ["orders.read"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    assert {:error, {:redirect, _}} = live(conn, ~p"/staff/diagnostics")
  end
end
