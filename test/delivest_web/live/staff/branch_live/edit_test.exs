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

  test "branch settings open on their own page and save", %{conn: conn} do
    branch = insert(:branch, name: "Old name", slug: "old-name")

    {:ok, lv, html} = live(conn, ~p"/staff/branches/old-name/edit")
    refute html =~ "branch-crm"

    assert {:error, {:live_redirect, %{to: "/staff/branches"}}} =
             lv
             |> form("#branch-form", branch_form: %{name: "New name", slug: "new-name"})
             |> render_submit()

    assert Repo.reload!(branch).name == "New name"
  end

  test "a new branch is created from the page", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/staff/branches/new")

    assert {:error, {:live_redirect, %{to: "/staff/branches"}}} =
             lv
             |> form("#branch-form", branch_form: %{name: "Fresh", slug: "fresh"})
             |> render_submit()

    assert Repo.get_by(Branch, slug: "fresh")
  end

  test "taken slug is shown on the form", %{conn: conn} do
    insert(:branch, slug: "taken")
    insert(:branch, slug: "mine")

    {:ok, lv, _html} = live(conn, ~p"/staff/branches/mine/edit")

    html = lv |> form("#branch-form", branch_form: %{slug: "taken"}) |> render_submit()
    assert html =~ "has already been taken"
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

    {:ok, lv, _html} = live(conn, ~p"/staff/branches/located/edit")

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

    {:ok, lv, html} = live(conn, ~p"/staff/branches/typed/edit")
    refute html =~ "branch-location-map"

    lv
    |> form("#branch-form", branch_form: %{latitude: "55.75", longitude: "37.61"})
    |> render_submit()

    assert %{latitude: 55.75} =
             Repo.get_by!(Branch, slug: "typed") |> Repo.preload(:info) |> Map.get(:info)
  end

  test "unknown branch goes back to the list", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/staff/branches"}}} =
             live(conn, ~p"/staff/branches/missing/edit")
  end
end
