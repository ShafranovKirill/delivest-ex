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

  test "the dark theme color is automatic until a custom one is chosen", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/staff/franchise")

    refute has_element?(lv, "#franchise-dark-color-input")

    lv |> element("#franchise-dark-color-custom") |> render_click()
    assert has_element?(lv, "#franchise-dark-color-preview")

    lv
    |> form("#franchise-settings-form", settings: %{dark_primary_color: "#e06b7d"})
    |> render_submit()

    assert %{dark_primary_color: "#e06b7d"} = Franchise.get_settings()

    lv |> element("#franchise-dark-color-auto") |> render_click()
    refute has_element?(lv, "#franchise-dark-color-input")

    lv |> form("#franchise-settings-form") |> render_submit()
    assert %{dark_primary_color: nil} = Franchise.get_settings()
  end

  test "uploads the icon and the link preview, then removes the icon", %{conn: conn} do
    Delivest.S3Stub.record(self())
    {:ok, lv, _html} = live(conn, ~p"/staff/franchise")

    lv
    |> file_input("#franchise-images-form", :icon, [
      %{name: "logo.png", content: Delivest.S3Stub.png(512, 512), type: "image/png"}
    ])
    |> render_upload("logo.png")

    assert %{icon_key: "franchise/icon/" <> _} = Franchise.get_settings()
    assert has_element?(lv, "#franchise-icon-preview")

    lv
    |> file_input("#franchise-images-form", :share_image, [
      %{name: "tiny.png", content: Delivest.S3Stub.png(100, 100), type: "image/png"}
    ])
    |> render_upload("tiny.png")

    assert render(lv) =~ "at least 600 px wide"
    refute has_element?(lv, "#franchise-share-preview")

    lv |> element("button[phx-value-image=icon]") |> render_click()

    assert %{icon_key: nil} = Franchise.get_settings()
    refute has_element?(lv, "#franchise-icon-preview")
  end

  test "uploads a logo for each theme and falls back to the name", %{conn: conn} do
    Delivest.S3Stub.record(self())
    {:ok, lv, html} = live(conn, ~p"/staff/franchise")

    assert html =~ "Delivest"
    refute has_element?(lv, "#franchise-logo-preview")

    lv
    |> file_input("#franchise-logo-form", :logo, [
      %{name: "logo.png", content: Delivest.S3Stub.png(800, 200), type: "image/png"}
    ])
    |> render_upload("logo.png")

    assert %{logo_key: "franchise/logo/" <> _} = Franchise.get_settings()
    assert has_element?(lv, "#franchise-logo-preview")
    assert has_element?(lv, "#franchise-logo-dark-preview")

    lv
    |> file_input("#franchise-logo-form", :logo_dark, [
      %{name: "flat.png", content: Delivest.S3Stub.png(400, 20), type: "image/png"}
    ])
    |> render_upload("flat.png")

    assert render(lv) =~ "at least 48 px high"
    assert %{logo_dark_key: nil} = Franchise.get_settings()

    lv |> element("button[phx-value-image=logo]") |> render_click()

    assert %{logo_key: nil} = Franchise.get_settings()
    refute has_element?(lv, "#franchise-logo-preview")
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
