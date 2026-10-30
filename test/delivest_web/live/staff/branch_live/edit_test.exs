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
    refute html =~ "couriers"

    for section <- ~w(general location hours kitchen board links ycart) do
      assert has_element?(
               lv,
               ~s(#branch-section-#{section}[href="/staff/branches/split/edit/#{section}"])
             )
    end

    assert {:error, {:live_redirect, %{to: "/staff/branches/split/edit"}}} =
             live(conn, ~p"/staff/branches/split/edit/unknown")
  end

  test "a section saves and goes back to the sections", %{conn: conn} do
    branch = insert(:branch, name: "Old name", slug: "old-name")

    {:ok, lv, _html} = live(conn, ~p"/staff/branches/old-name/edit/general")
    refute has_element?(lv, "#branch-form input[name='branch_form[vk_url]']")

    assert {:error, {:live_redirect, %{to: "/staff/branches/new-name/edit"}}} =
             lv
             |> form("#branch-form", branch_form: %{name: "New name", slug: "new-name"})
             |> render_submit()

    assert Repo.reload!(branch).name == "New name"
  end

  test "a new branch is created from the page", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/staff/branches/new")

    assert {:error, {:live_redirect, %{to: "/staff/branches/fresh/edit"}}} =
             lv
             |> form("#branch-form", branch_form: %{name: "Fresh", slug: "fresh"})
             |> render_submit()

    assert Repo.get_by(Branch, slug: "fresh")
  end

  test "taken slug is shown on the form", %{conn: conn} do
    insert(:branch, slug: "taken")
    insert(:branch, slug: "mine")

    {:ok, lv, _html} = live(conn, ~p"/staff/branches/mine/edit/general")

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
end
