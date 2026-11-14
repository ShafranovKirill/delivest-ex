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

  test "metrics and log pages expose every data and system route", %{conn: conn} do
    staff = insert(:staff, role: build(:role, permissions: ["logs.read"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    for {path, active} <- [
          {~p"/staff/diagnostics", "metrics"},
          {~p"/staff/logs", "events"},
          {~p"/staff/logs/errors", "errors"}
        ] do
      {:ok, view, _} = live(conn, path)

      assert has_element?(view, "#sidebar-group-settings[open] #sidebar-group-data-system[open]")
      assert has_element?(view, "#sidebar-logs-tab-#{active}[aria-current='page']")

      assert has_element?(
               view,
               "#staff-context-navigation #logs-tab-#{active}[aria-current='page']"
             )

      for {id, href} <- [
            {"metrics", "/staff/diagnostics"},
            {"events", "/staff/logs"},
            {"raw", "/staff/logs/raw"},
            {"errors", "/staff/logs/errors"}
          ] do
        assert has_element?(
                 view,
                 "#sidebar-group-data-system #sidebar-logs-tab-#{id}[href='#{href}']"
               )

        assert has_element?(view, "#staff-context-navigation #logs-tab-#{id}[href='#{href}']")
      end

      refute has_element?(view, "#sidebar-group-settings > #sidebar-staff-page-header-navigation")
    end
  end
end
