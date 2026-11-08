defmodule DelivestWeb.Staff.FranchiseLive.IndexTest do
  use DelivestWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Franchise

  setup %{conn: conn} do
    Cachex.clear(:franchise_cache)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    %{conn: init_test_session(conn, %{"staff_id" => staff.id}), staff: staff}
  end

  test "settings are split into sections", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/staff/franchise")

    for section <- ~w(brand seller loyalty logo images documents) do
      assert has_element?(
               lv,
               ~s(#franchise-section-#{section}[href="/staff/franchise/#{section}"])
             )
    end

    refute has_element?(lv, "#franchise-settings-form")

    assert {:error, {:live_redirect, %{to: "/staff/franchise"}}} =
             live(conn, ~p"/staff/franchise/unknown")
  end

  test "saves brand and seller details", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/staff/franchise/brand")

    assert has_element?(lv, ~s(#franchise-settings-form select[name="settings[default_theme]"]))
    refute has_element?(lv, ~s(#franchise-settings-form input[name="settings[yandex_org_id]"]))
    refute has_element?(lv, ~s(#franchise-settings-form input[name="settings[yandex_api_key]"]))

    lv
    |> form("#franchise-settings-form", settings: %{primary_color: "#eeeeee"})
    |> render_change()

    assert has_element?(lv, "#franchise-color-warning")

    lv
    |> form("#franchise-settings-form",
      settings: %{name: "Pizza", primary_color: "#aa0000", default_theme: "dark"}
    )
    |> render_submit()

    {:ok, lv, _html} = live(conn, ~p"/staff/franchise/seller")
    refute has_element?(lv, "#franchise-color")

    lv
    |> form("#franchise-settings-form", settings: %{inn: "7700000000"})
    |> render_submit()

    assert %{name: "Pizza", primary_color: "#aa0000", default_theme: "dark", inn: "7700000000"} =
             Franchise.get_settings()
  end

  test "admin enters a manual Yandex rating on the brand page", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/staff/franchise/brand")

    assert has_element?(lv, "#franchise-yandex-rating-form")

    lv
    |> form("#franchise-yandex-rating-form", rating: %{rating: "4.8", reviews_count: "26"})
    |> render_submit()

    assert %{rating: 4.8, reviews_count: 26} = Delivest.Franchise.Rating.current(:yandex)
  end

  test "the dark theme color is automatic until a custom one is chosen", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/staff/franchise/brand")

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
    {:ok, lv, _html} = live(conn, ~p"/staff/franchise/images")

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
    {:ok, lv, html} = live(conn, ~p"/staff/franchise/logo")

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

  test "shows full instance controls and agent outage", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/staff/franchise/snapshot")
    assert has_element?(lv, "#backup-export")
    assert has_element?(lv, "#backup-import-form input[type=file]")
    assert has_element?(lv, "#backup-confirm")
    assert has_element?(lv, "#backup-agent-unavailable")
    refute has_element?(lv, ~s(input[name="sections[]"]))
  end

  test "admin creates a durable full backup from the page", %{conn: conn, staff: staff} do
    dir = prepare_backup_agent!()
    {:ok, lv, _html} = live(conn, ~p"/staff/franchise/snapshot")
    refute has_element?(lv, "#backup-agent-unavailable")

    lv |> element("#backup-export") |> render_click()

    assert %{"action" => "export", "requested_by" => owner} =
             Delivest.InstanceBackup.active().request

    assert owner == staff.id
    assert has_element?(lv, "#backup-phase")
    assert File.dir?(Path.join(dir, "jobs"))
  end

  test "restore requires confirmation then stores the upload on disk", %{conn: conn} do
    prepare_backup_agent!()
    {:ok, lv, _html} = live(conn, ~p"/staff/franchise/snapshot")

    upload =
      file_input(lv, "#backup-import-form", :instance_archive, [
        %{name: "restore.tar", content: "tar payload", type: "application/x-tar"}
      ])

    assert render_upload(upload, "restore.tar")
    lv |> form("#backup-import-form") |> render_submit()
    assert Delivest.InstanceBackup.active() == nil

    lv |> form("#backup-import-form", %{"confirm" => "replace"}) |> render_submit()
    assert %{"action" => "import"} = Delivest.InstanceBackup.active().request
    id = Delivest.InstanceBackup.active().id

    assert File.read!(Path.join(Delivest.InstanceBackup.job_dir(id), "archive.tar")) ==
             "tar payload"
  end

  test "the franchise snapshot is closed to non-admin staff", %{conn: conn} do
    prepare_backup_agent!()
    staff = insert(:staff, role: insert(:role, permissions: ["franchise.update"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, lv, _html} = live(conn, ~p"/staff/franchise")
    refute has_element?(lv, "#franchise-section-snapshot")

    {:ok, lv, _html} = live(conn, ~p"/staff/franchise/snapshot")
    assert has_element?(lv, "#snapshot-forbidden")
    refute has_element?(lv, "#backup-export")

    render_hook(lv, "backup_export", %{})
    render_hook(lv, "backup_import", %{"confirm" => "replace"})
    assert Delivest.InstanceBackup.active() == nil

    assert conn
           |> get("/staff/franchise/instance-backup/#{Ecto.UUID.generate()}")
           |> response(404)

    assert conn |> get(~p"/staff/franchise/site-snapshot?sections[]=franchise") |> response(302)
  end

  defp prepare_backup_agent! do
    dir = Path.join(System.tmp_dir!(), "live-backup-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    previous = Application.get_env(:delivest, :instance_backup_dir)
    Application.put_env(:delivest, :instance_backup_dir, dir)

    Delivest.InstanceBackup.write_json(Path.join(dir, "heartbeat.json"), %{
      protocol: 1,
      updated_at: DateTime.utc_now()
    })

    on_exit(fn ->
      Application.put_env(:delivest, :instance_backup_dir, previous)
      File.rm_rf!(dir)
    end)

    dir
  end
end
