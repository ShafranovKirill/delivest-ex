defmodule DelivestWeb.Staff.FoundationGalleryLiveTest do
  use DelivestWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Delivest.Factory

  setup %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    %{conn: init_test_session(conn, %{"staff_id" => staff.id})}
  end

  test "gallery route requires staff", %{conn: _conn} do
    assert {:error, {:redirect, %{to: "/staff/auth/login"}}} =
             live(Phoenix.ConnTest.build_conn(), "/staff/foundation-gallery")
  end

  test "four page types share one content title and existing shell", %{conn: conn} do
    for page <- ~w(queue list entity settings) do
      {:ok, view, _html} = live(conn, "/staff/foundation-gallery?view=#{page}")
      assert has_element?(view, "#main-sidebar")
      assert has_element?(view, "#gallery-header h1")
      refute has_element?(view, "#staff-header h1")
      assert has_element?(view, "#gallery-#{page}")
    end
  end

  test "URL query filters on server, reset clears it and selection is page scoped", %{conn: conn} do
    {:ok, view, _} = live(conn, "/staff/foundation-gallery?view=list&page=2")
    assert has_element?(view, "#gallery-products-row-p1") == false
    assert has_element?(view, "#gallery-products-row-p2")
    assert has_element?(view, "#gallery-products nav[aria-label='Pagination']")

    {:ok, filtered, _} = live(conn, "/staff/foundation-gallery?view=list&q=not-found&page=3")
    assert has_element?(filtered, "#gallery-products", "Nothing found")

    assert has_element?(
             filtered,
             "#gallery-products a[href='/staff/foundation-gallery?view=list']",
             "Reset filters"
           )

    filtered |> element("#product-filters a", "Reset") |> render_click()
    assert has_element?(filtered, "#gallery-products-row-p1")
  end

  test "entity follows selected fixture and return URL restores list", %{conn: conn} do
    return = "/staff/foundation-gallery?view=list&q=soup&page=1"

    url =
      "/staff/foundation-gallery?" <>
        URI.encode_query(%{"view" => "entity", "id" => "p2", "return" => return})

    {:ok, view, _} = live(conn, url)
    assert has_element?(view, "#gallery-entity h2", "Mushroom soup")
    assert has_element?(view, "#gallery-entity a[href='#{return}']")
  end

  test "branch fixture form validates with domain changeset and keeps draft on error", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/staff/foundation-gallery?view=settings")

    view
    |> form("#gallery-branch-form", branch: %{name: "X", code: "?", slug: "demo"})
    |> render_submit()

    assert has_element?(view, "#branch-errors a[href='#branch-name']")

    error_text =
      view |> element("#branch-errors") |> render() |> LazyHTML.from_fragment() |> LazyHTML.text()

    refute String.contains?(error_text, "%{")
    assert has_element?(view, "#branch-name[value='X']")
    view |> element("#branch-actions button[type='button']") |> render_click()
    assert has_element?(view, "#discard-dialog")
    view |> element("#discard-dialog button", "Stay") |> render_click()
    assert has_element?(view, "#branch-name[value='X']")
  end

  test "bulk confirmation states exact page scope and returns per-record result", %{conn: conn} do
    {:ok, view, _} = live(conn, "/staff/foundation-gallery?view=list")
    view |> element("#gallery-products-row-p1 input[type=checkbox]") |> render_click()
    assert has_element?(view, "#gallery-bulk", "Selected 1 on this page")
    view |> element("#gallery-bulk-request") |> render_click()
    assert has_element?(view, "#bulk-dialog", "1 fixture products on this page")
    view |> element("#bulk-dialog button", "Archive selected products") |> render_click()
    assert has_element?(view, "#gallery-bulk-result", "1 fixture records accepted")
  end

  test "table cells render custom badge and row action without following the name link", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/staff/foundation-gallery?view=list")
    assert has_element?(view, "#gallery-products-row-p1 a[href*='view=entity']")
    assert has_element?(view, "#gallery-products-row-p1 input[phx-click='select']")
    assert has_element?(view, "#gallery-products-row-p1 #product-status-p1", "Active")
    view |> element("#product-action-p1") |> render_click()
    assert has_element?(view, "#gallery-panel")
    assert has_element?(view, "#gallery-list")
  end

  test "scope switcher searches allowed fixture scopes and resets paging", %{conn: conn} do
    {:ok, view, _} = live(conn, "/staff/foundation-gallery?view=list&page=2")
    view |> form("#gallery-scope-search-form", q: "Demo") |> render_change()
    assert has_element?(view, "#gallery-scope a", "Demo branch")
    refute has_element?(view, "#gallery-scope a", "Network")
    view |> element("#gallery-scope a", "Demo branch") |> render_click()

    assert_patch(
      view,
      "/staff/foundation-gallery?" <>
        URI.encode_query(%{
          "direction" => "asc",
          "page" => 1,
          "per_page" => 25,
          "q" => "",
          "scope" => "branch-a",
          "sort" => "name",
          "view" => "list"
        })
    )

    assert has_element?(view, "#gallery-scope", "Demo branch")
  end

  test "density, feature state, picker and leave confirmation are interactive", %{conn: conn} do
    {:ok, list, _} = live(conn, "/staff/foundation-gallery?view=list")
    list |> element("#gallery-density button", "Compact") |> render_click()
    assert has_element?(list, "#foundation-gallery[data-density='compact']")

    {:ok, entity, _} = live(conn, "/staff/foundation-gallery?view=entity&id=p1")
    entity |> element("#open-product-picker") |> render_click()
    assert has_element?(entity, "#gallery-product-picker[role='dialog']")

    {:ok, settings, _} = live(conn, "/staff/foundation-gallery?view=settings")
    settings |> element("#feature-toggle") |> render_click()
    assert has_element?(settings, "#feature-example", "Request enable")

    settings
    |> form("#gallery-branch-form", branch: %{name: "Changed", code: "DEMO", slug: "demo"})
    |> render_change()

    render_hook(settings, "request_leave", %{"to" => "/staff/foundation-gallery?view=list"})
    assert has_element?(settings, "#leave-dialog")
    settings |> element("#leave-dialog button", "Stay") |> render_click()
    refute has_element?(settings, "#leave-dialog")
    assert has_element?(settings, "#branch-name[value='Changed']")
  end

  test "connection check fixture never activates a configured but disabled integration", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/staff/foundation-gallery?view=settings")

    assert has_element?(view, "#integration-unconfigured-connection", "Unknown")
    assert has_element?(view, "#integration-blocked-connection", "Connection error")
    assert has_element?(view, "#integration-stale-connection", "Check is stale")
    assert has_element?(view, "#integration-configured-effective", "No")
    assert has_element?(view, "#integration-configured", "Payments: Available")

    view |> element("#check-connection-configured") |> render_click()
    assert has_element?(view, "#integration-configured-connection", "Checking")
    assert has_element?(view, "#integration-configured-effective", "No")

    view |> element("#finish-connection-configured") |> render_click()
    assert has_element?(view, "#integration-configured-connection", "Connected")
    assert has_element?(view, "#integration-configured-effective", "No")
    assert has_element?(view, "#integration-configured", "Payments: Available")
  end

  test "server rejects history patch while branch draft is dirty", %{conn: conn} do
    {:ok, view, _} = live(conn, "/staff/foundation-gallery?view=settings")

    view
    |> form("#gallery-branch-form", branch: %{name: "Changed", code: "DEMO", slug: "demo"})
    |> render_change()

    render_patch(view, "/staff/foundation-gallery?view=list")
    assert has_element?(view, "#gallery-settings")
    assert has_element?(view, "#leave-dialog")
    view |> element("#leave-dialog button", "Stay") |> render_click()
    assert has_element?(view, "#branch-name[value='Changed']")
  end

  test "confirmed leave discards draft and future edits are guarded again", %{conn: conn} do
    {:ok, view, _} = live(conn, "/staff/foundation-gallery?view=settings")

    view
    |> form("#gallery-branch-form", branch: %{name: "First draft", code: "DEMO", slug: "demo"})
    |> render_change()

    render_patch(view, "/staff/foundation-gallery?view=list")
    view |> element("#leave-dialog button", "Leave without saving") |> render_click()
    assert_patch(view, "/staff/foundation-gallery?view=list")
    render_patch(view, "/staff/foundation-gallery?view=settings")
    assert has_element?(view, "#branch-name[value='Demo branch']")

    view
    |> form("#gallery-branch-form", branch: %{name: "Second draft", code: "DEMO", slug: "demo"})
    |> render_change()

    render_patch(view, "/staff/foundation-gallery?view=list")
    assert has_element?(view, "#leave-dialog")
  end

  test "dirty short panel requires confirmation for close and Escape event", %{conn: conn} do
    {:ok, view, _} = live(conn, "/staff/foundation-gallery?view=list")
    view |> element("#gallery-primary") |> render_click()
    view |> form("#gallery-panel-form", note: "Draft note") |> render_change()
    assert has_element?(view, "#gallery-panel[data-dirty='true']")
    render_hook(view, "request_close", %{})
    assert has_element?(view, "#panel-discard-dialog")
    view |> element("#panel-discard-dialog button", "Stay") |> render_click()
    assert has_element?(view, "#gallery-panel-note[value='Draft note']")
    view |> element("#gallery-panel button[aria-label='Close panel']") |> render_click()
    assert has_element?(view, "#panel-discard-dialog")
    view |> element("#panel-discard-dialog button", "Discard note") |> render_click()
    refute has_element?(view, "#gallery-panel")
  end

  test "settings renders server error, conflict and view-only state without losing draft", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/staff/foundation-gallery?view=settings")

    view
    |> form("#gallery-branch-form", branch: %{name: "Changed", code: "DEMO", slug: "demo"})
    |> render_change()

    view |> element("#simulate-server-error") |> render_click()

    assert has_element?(
             view,
             "#branch-errors a[href='#gallery-branch-form']",
             "Server unavailable"
           )

    assert has_element?(view, "#branch-name[value='Changed']")
    view |> element("#simulate-conflict") |> render_click()
    assert has_element?(view, "#branch-actions [role='alert']", "Changes conflict")
    assert has_element?(view, "#branch-actions button[type='submit'][disabled]")
    assert has_element?(view, "#branch-name[value='Changed']")
    view |> element("#conflict-reload") |> render_click()
    assert has_element?(view, "#reload-dialog")
    view |> element("#reload-dialog button", "Stay") |> render_click()
    assert has_element?(view, "#branch-name[value='Changed']")
    view |> element("#conflict-retry") |> render_click()
    assert has_element?(view, "#branch-name[value='Changed']")
    refute has_element?(view, "#branch-actions button[type='submit'][disabled]")
    view |> element("#simulate-conflict") |> render_click()
    view |> element("#conflict-reload") |> render_click()
    view |> element("#reload-dialog button", "Reload latest") |> render_click()
    assert has_element?(view, "#branch-name[value='Latest branch']")
    view |> element("#simulate-read-only") |> render_click()
    assert has_element?(view, "#branch-name[disabled]")
    assert has_element?(view, "#branch-actions button[type='submit'][disabled]")
  end
end
