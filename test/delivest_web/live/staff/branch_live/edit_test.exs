defmodule DelivestWeb.Staff.BranchLive.EditTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Identity.Branch
  alias Delivest.Repo

  setup %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    %{conn: init_test_session(conn, %{"staff_id" => staff.id})}
  end

  test "branch settings are split into sections", %{conn: conn} do
    insert(:branch, slug: "split")

    {:ok, lv, html} = live(conn, ~p"/staff/branches/split/edit")
    refute html =~ "branch-form"
    assert has_element?(lv, "#branch-delivery-card[href='/staff/b/split/delivery']")

    for section <- ~w(general fulfillment location hours kitchen board links) do
      assert has_element?(
               lv,
               ~s(#branch-section-#{section}[href="/staff/branches/split/edit/#{section}"])
             )
    end

    refute has_element?(lv, "#branch-section-ycart")

    assert {:error, {:live_redirect, %{to: "/staff/branches/split/edit"}}} =
             live(conn, ~p"/staff/branches/split/edit/unknown")
  end

  test "legacy YCart URL redirects only staff with integration read access", %{conn: conn} do
    branch = insert(:branch, slug: "legacy-ycart")

    assert {:error, {:live_redirect, %{to: "/staff/b/legacy-ycart/integrations/ycart"}}} =
             live(conn, ~p"/staff/branches/#{branch.slug}/edit/ycart")

    branch_editor =
      insert(:staff,
        role: insert(:role, permissions: ["branches.read", "branches.update"])
      )

    insert(:staff_branch, staff: branch_editor, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => branch_editor.id})

    assert {:error, {:live_redirect, %{to: "/staff/branches"}}} =
             live(conn, ~p"/staff/branches/#{branch.slug}/edit/ycart")
  end

  test "branch form ignores submitted YCart fields" do
    alias DelivestWeb.Staff.BranchLive.BranchForm

    changeset =
      BranchForm.new()
      |> BranchForm.changeset(%{
        "name" => "Without YCart",
        "slug" => "without-ycart",
        "ycart_settings" => %{"enabled" => true, "yandex_org_id" => "123"}
      })

    {_branch_params, info_params} = BranchForm.to_params(changeset)
    refute Map.has_key?(info_params, "ycart_settings")
  end

  test "a section saves and goes back to the sections", %{conn: conn} do
    branch = insert(:branch, name: "Old name", slug: "old-name")

    {:ok, lv, _html} = live(conn, ~p"/staff/branches/old-name/edit/general")
    refute has_element?(lv, "#branch-form input[name='branch_form[vk_url]']")

    assert has_element?(lv, "#staff-page-header-actions button[form='branch-form']")

    refute has_element?(lv, "#branch-form button[type='submit']")

    assert {:error, {:live_redirect, %{to: "/staff/branches/new-name/edit"}}} =
             lv
             |> form("#branch-form", branch_form: %{name: "New name", slug: "new-name"})
             |> render_submit()

    assert Repo.reload!(branch).name == "New name"
  end

  test "working day can be turned off and back on without losing its hours", %{conn: conn} do
    branch = insert(:branch, slug: "weekly-hours")
    path = ~p"/staff/branches/#{branch.slug}/edit/hours"

    {:ok, view, _} = live(conn, path)

    assert {:error, {:live_redirect, _}} =
             view
             |> form("#branch-form",
               branch_form: %{
                 working_hours: %{
                   monday: %{enabled: "true", open: "09:00", close: "18:00"}
                 }
               }
             )
             |> render_submit()

    {:ok, view, _} = live(conn, path)

    assert has_element?(
             view,
             "input[name='branch_form[working_hours][monday][enabled]'][type='checkbox'][checked]"
           )

    assert {:error, {:live_redirect, _}} =
             view
             |> form("#branch-form",
               branch_form: %{working_hours: %{monday: %{enabled: "false"}}}
             )
             |> render_submit()

    assert %{"enabled" => false, "open" => "09:00", "close" => "18:00"} =
             Repo.preload(branch, :info, force: true).info.working_hours["monday"]

    {:ok, view, _} = live(conn, path)

    refute has_element?(
             view,
             "input[name='branch_form[working_hours][monday][enabled]'][type='checkbox'][checked]"
           )

    assert has_element?(
             view,
             "input[name='branch_form[working_hours][monday][open]'][value='09:00']"
           )

    assert {:error, {:live_redirect, _}} =
             view
             |> form("#branch-form", branch_form: %{working_hours: %{monday: %{enabled: "true"}}})
             |> render_submit()

    assert %{"enabled" => true, "open" => "09:00", "close" => "18:00"} =
             Repo.preload(branch, :info, force: true).info.working_hours["monday"]
  end

  test "revoked branch update permission blocks an open form", %{conn: conn} do
    branch = insert(:branch, name: "Original", slug: "revoked-form")
    role = insert(:role, permissions: ["branches.read", "branches.update"])
    staff = insert(:staff, role: role)
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, lv, _} = live(conn, ~p"/staff/branches/#{branch.slug}/edit/general")
    role |> Ecto.Changeset.change(permissions: ["branches.read"]) |> Repo.update!()

    lv
    |> form("#branch-form", branch_form: %{name: "Forbidden change"})
    |> render_submit()

    assert Repo.reload!(branch).name == "Original"
  end

  test "a new branch is created from the page", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/staff/branches/new")
    refute has_element?(lv, "#branch-delete-section")

    assert {:error, {:live_redirect, %{to: "/staff/branches/fresh/edit"}}} =
             lv
             |> form("#branch-form", branch_form: %{name: "Fresh", slug: "fresh"})
             |> render_submit()

    assert Repo.get_by(Branch, slug: "fresh")
  end

  test "branch deletion stays collapsed, requires exact name, and resets on cancel", %{
    conn: conn
  } do
    branch = insert(:branch, name: "Delete me", slug: "delete-me")
    {:ok, overview, _} = live(conn, ~p"/staff/branches/#{branch.slug}/edit")
    refute has_element?(overview, "#branch-delete-section")

    {:ok, lv, _} = live(conn, ~p"/staff/branches/#{branch.slug}/edit/general")
    assert has_element?(lv, "#branch-delete-open[aria-expanded='false']")
    refute has_element?(lv, "#branch-delete-form")

    lv |> element("#branch-delete-open") |> render_click()
    assert has_element?(lv, "#branch-delete-open[aria-expanded='true']")
    assert has_element?(lv, "#branch-delete-confirm[disabled]")

    lv |> form("#branch-delete-form", confirmation: %{name: "wrong"}) |> render_change()
    assert has_element?(lv, "#branch-delete-confirm[disabled]")
    lv |> render_hook("confirm_delete", %{"confirmation" => %{"name" => "wrong"}})
    assert is_nil(Repo.reload!(branch).deleted_at)

    lv |> element("#branch-delete-form button[phx-click='cancel_delete']") |> render_click()
    refute has_element?(lv, "#branch-delete-form")
    lv |> element("#branch-delete-open") |> render_click()
    assert has_element?(lv, "#branch-delete-confirm[disabled]")

    lv |> form("#branch-delete-form", confirmation: %{name: "Delete me"}) |> render_change()
    refute has_element?(lv, "#branch-delete-confirm[disabled]")

    assert {:error, {:live_redirect, %{to: "/staff/branches"}}} =
             lv |> form("#branch-delete-form") |> render_submit()

    assert Repo.reload!(branch).deleted_at
  end

  test "without branches.delete the general page has no deletion section", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["branches.read", "branches.update"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, lv, _} = live(conn, ~p"/staff/branches/#{branch.slug}/edit/general")
    refute has_element?(lv, "#branch-delete-section")
    lv |> render_hook("confirm_delete", %{"confirmation" => %{"name" => branch.name}})
    assert is_nil(Repo.reload!(branch).deleted_at)
  end

  test "manual rating can be saved and cleared", %{conn: conn} do
    branch = insert(:branch, slug: "rated")

    {:ok, lv, _html} = live(conn, ~p"/staff/branches/rated/edit/general")

    assert {:error, {:live_redirect, _}} =
             lv
             |> form("#branch-form", branch_form: %{manual_rating: "4.5"})
             |> render_submit()

    assert %{manual_rating: 4.5} = Repo.preload(branch, :info, force: true).info

    {:ok, lv, _html} = live(conn, ~p"/staff/branches/rated/edit/general")
    lv |> element("button[phx-click='clear_rating']") |> render_click()

    assert {:error, {:live_redirect, _}} = lv |> form("#branch-form") |> render_submit()
    assert %{manual_rating: nil} = Repo.preload(branch, :info, force: true).info
  end

  test "taken slug is shown on the form", %{conn: conn} do
    insert(:branch, slug: "taken")
    insert(:branch, slug: "mine")

    {:ok, lv, _html} = live(conn, ~p"/staff/branches/mine/edit/general")

    html = lv |> form("#branch-form", branch_form: %{slug: "taken"}) |> render_submit()
    assert html =~ "has already been taken"
  end

  test "stale branch form keeps the draft and requires an explicit reload", %{conn: conn} do
    branch = insert(:branch, name: "Original", slug: "stale-branch")
    {:ok, lv, _html} = live(conn, ~p"/staff/branches/stale-branch/edit/general")

    branch |> Branch.changeset(%{"name" => "External change"}) |> Repo.update!()

    lv
    |> form("#branch-form", branch_form: %{name: "My draft"})
    |> render_submit()

    assert has_element?(lv, "#branch-form-conflict[role='alert']")
    assert has_element?(lv, "#branch-form input[name='branch_form[name]'][value='My draft']")
    assert Repo.reload!(branch).name == "External change"

    lv |> element("#branch-form-conflict button[phx-click='reload']") |> render_click()
    refute has_element?(lv, "#branch-form-conflict")

    assert has_element?(
             lv,
             "#branch-form input[name='branch_form[name]'][value='External change']"
           )
  end

  test "the branch point is found by address and moved on the map", %{conn: conn} do
    Repo.insert!(%Delivest.Integrations.Dadata.Settings{api_key: "key", enabled: true})
    branch = insert(:branch, slug: "located")

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{
        "suggestions" => [
          %{
            "value" => "г Тюмень, ул Республики, д 10",
            "data" => %{
              "city" => "Тюмень",
              "street_with_type" => "ул Республики",
              "house" => "10",
              "geo_lat" => "57.15",
              "geo_lon" => "65.53"
            }
          }
        ]
      })
    end)

    {:ok, lv, _html} = live(conn, ~p"/staff/branches/located/edit/location")

    lv
    |> element("#branch-form")
    |> render_change(%{"_target" => ["location_query"], "location_query" => "республики 10"})

    lv |> element("#location-suggestions button") |> render_click()
    assert_push_event(lv, "location:center", %{lat: 57.15, lng: 65.53})

    lv
    |> element("#branch-location-map")
    |> render_hook("location_moved", %{lat: 57.2, lng: 65.6})

    assert {:error, {:live_redirect, _}} = lv |> form("#branch-form") |> render_submit()

    assert %{
             address: "г Тюмень, ул Республики, д 10",
             city: "Тюмень",
             latitude: 57.2,
             longitude: 65.6
           } = Repo.preload(branch, :info, force: true).info
  end

  test "without the map the point is typed in", %{conn: conn} do
    insert(:branch, slug: "typed")

    {:ok, lv, html} = live(conn, ~p"/staff/branches/typed/edit/location")
    refute html =~ "branch-location-map"

    lv
    |> form("#branch-form", branch_form: %{latitude: "55.75", longitude: "37.61"})
    |> render_submit()

    assert %{latitude: 55.75} =
             Repo.get_by!(Branch, slug: "typed") |> Repo.preload(:info) |> Map.get(:info)
  end

  test "the pickup board link is created in its section", %{conn: conn} do
    insert(:branch, slug: "board")

    {:ok, lv, _html} = live(conn, ~p"/staff/branches/board/edit/board")
    refute has_element?(lv, "#board-url")

    lv |> element("#board-reset") |> render_click()

    assert lv |> element("#board-url") |> render() =~ "/board/"
  end

  test "unknown branch goes back to the list", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/staff/branches"}}} =
             live(conn, ~p"/staff/branches/missing/edit")
  end

  test "a special day is added, listed and removed", %{conn: conn} do
    insert(:branch, slug: "holidays")
    date = Date.to_iso8601(Date.add(Date.utc_today(), 10))

    {:ok, lv, _html} = live(conn, ~p"/staff/branches/holidays/edit/hours")

    lv
    |> form("#special-hours-form", %{"date" => date, "open" => "10:00", "close" => "18:00"})
    |> render_submit()

    assert has_element?(lv, "#special-day-#{date}", "10:00")

    lv |> element("#special-day-#{date} button") |> render_click()
    refute has_element?(lv, "#special-day-#{date}")
  end

  test "fulfillment settings save independently and allow all methods off", %{conn: conn} do
    branch = insert(:branch, slug: "methods")

    for attrs <- [
          %{delivery: "false", pickup: "false", dine_in: "true"},
          %{delivery: "false", pickup: "false", dine_in: "false"}
        ] do
      {:ok, lv, _} = live(conn, ~p"/staff/branches/methods/edit/fulfillment")
      assert has_element?(lv, "input[name='branch_form[fulfillment][delivery]']")

      assert {:error, {:live_redirect, %{to: "/staff/branches/methods/edit"}}} =
               lv |> form("#branch-form", branch_form: %{fulfillment: attrs}) |> render_submit()

      settings =
        Repo.get_by!(Delivest.Identity.Branch.BranchInfo, branch_id: branch.id).fulfillment

      assert settings.delivery == false
      assert settings.pickup == false
      assert settings.dine_in == (attrs.dine_in == "true")
    end
  end

  test "staff can disable and restore customer cancellation for one branch", %{conn: conn} do
    branch = insert(:branch, slug: "cancel-setting")
    other = insert(:branch, slug: "other-cancel-setting")
    Repo.insert!(%Delivest.Identity.Branch.BranchInfo{branch_id: other.id})

    for {value, expected} <- [{"false", false}, {"true", true}] do
      {:ok, lv, _} = live(conn, ~p"/staff/branches/#{branch.slug}/edit/fulfillment")
      assert has_element?(lv, "input[name='branch_form[fulfillment][client_cancellation]']")

      assert {:error, {:live_redirect, _}} =
               lv
               |> form("#branch-form", branch_form: %{fulfillment: %{client_cancellation: value}})
               |> render_submit()

      {:ok, reloaded, _} = live(conn, ~p"/staff/branches/#{branch.slug}/edit/fulfillment")

      assert has_element?(
               reloaded,
               "input[name='branch_form[fulfillment][client_cancellation]'][type='checkbox']"
             )

      assert Repo.get_by!(Delivest.Identity.Branch.BranchInfo, branch_id: branch.id).fulfillment.client_cancellation ==
               expected

      assert Repo.get_by!(Delivest.Identity.Branch.BranchInfo, branch_id: other.id).fulfillment.client_cancellation
    end
  end

  test "branch overview hides delivery without scoped permission", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["branches.read", "branches.update"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})
    {:ok, lv, _} = live(conn, ~p"/staff/branches/#{branch.slug}/edit")
    refute has_element?(lv, "#branch-delivery-card")
  end
end
