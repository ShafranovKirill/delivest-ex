defmodule DelivestWeb.Staff.AnalyticsSettingsTest do
  use DelivestWeb.ConnCase, async: false

  import Delivest.Factory
  import Phoenix.LiveViewTest

  alias Delivest.{Features, Repo}

  defp login(conn, permissions) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    {init_test_session(conn, %{"staff_id" => staff.id}), staff}
  end

  test "administrator can enable, reload and confirm disabling branch tracking", %{conn: conn} do
    branch = insert(:branch)
    {conn, _} = login(conn, ["admin"])
    {:ok, settings, _} = live(conn, ~p"/staff/branches/#{branch.slug}/edit")
    assert has_element?(settings, "#branch-section-analytics")
    {:ok, view, _} = live(conn, ~p"/staff/branches/#{branch.slug}/edit/analytics")
    refute has_element?(view, "#branch-save")
    assert has_element?(view, "#analytics-toggle-1[aria-checked=false]")
    view |> element("#analytics-toggle-1") |> render_click()
    assert Features.enabled?("analytics_funnel", {:branch, branch.id})
    {:ok, view, _} = live(conn, ~p"/staff/branches/#{branch.slug}/edit/analytics")
    assert has_element?(view, "#analytics-toggle-1[aria-checked=true]")
    view |> element("#analytics-toggle-1") |> render_click()
    assert has_element?(view, "#analytics-disable-confirmation")
    assert Features.enabled?("analytics_funnel", {:branch, branch.id})
    view |> element("#analytics-confirm-disable") |> render_click()
    refute Features.enabled?("analytics_funnel", {:branch, branch.id})
    assert Features.enabled?("analytics_funnel", :franchise)
  end

  test "branch editors cannot see or open tracking controls", %{conn: conn} do
    branch = insert(:branch)
    {conn, staff} = login(conn, ["branches.read", "branches.update", "franchise.update"])
    insert(:staff_branch, staff: staff, branch: branch)
    {:ok, view, _} = live(conn, ~p"/staff/branches/#{branch.slug}/edit")
    refute has_element?(view, "#branch-section-analytics")

    assert {:error, {:live_redirect, _}} =
             live(conn, ~p"/staff/branches/#{branch.slug}/edit/analytics")

    {:ok, view, _} = live(conn, ~p"/staff/franchise")
    refute has_element?(view, "#franchise-section-analytics")
    assert {:error, {:live_redirect, _}} = live(conn, ~p"/staff/franchise/analytics")
  end

  test "forged component rows and revoked administrator cannot change features", %{conn: conn} do
    branch = insert(:branch)
    {conn, staff} = login(conn, ["admin"])
    {:ok, view, _} = live(conn, ~p"/staff/branches/#{branch.slug}/edit/analytics")

    view
    |> with_target("#branch-analytics-settings")
    |> render_click("toggle", %{"row" => "999", "feature" => "yandex_ads"})

    refute Features.enabled?("yandex_ads", :franchise)

    staff.role
    |> Ecto.Changeset.change(permissions: ["branches.read", "branches.update"])
    |> Repo.update!()

    view |> with_target("#branch-analytics-settings") |> render_click("toggle", %{"row" => "1"})
    refute Features.enabled?("analytics_funnel", :franchise)
    refute has_element?(view, "#analytics-toggle-1")
  end

  test "enabling a dormant parent requires explicit confirmation of other affected branches", %{
    conn: conn
  } do
    target = insert(:branch)
    other = insert(:branch, name: "Previously enabled branch")
    third = insert(:branch)
    {conn, _} = login(conn, ["admin"])
    {:ok, _} = Features.configure("analytics_funnel", {:branch, other.id}, true, actor: "host")
    refute Features.enabled?("analytics_funnel", :franchise)

    {:ok, view, _} = live(conn, ~p"/staff/branches/#{target.slug}/edit/analytics")
    view |> element("#analytics-toggle-1") |> render_click()
    assert has_element?(view, "#analytics-enable-confirmation", other.name)
    refute Features.enabled?("analytics_funnel", :franchise)
    refute Features.enabled?("analytics_funnel", {:branch, target.id})

    # A newly affected branch invalidates the stored confirmation under the parent lock.
    {:ok, _} = Features.configure("analytics_funnel", {:branch, third.id}, true, actor: "host")
    view |> element("#analytics-confirm-enable") |> render_click()
    assert has_element?(view, "#analytics-enable-confirmation", third.name)
    refute Features.enabled?("analytics_funnel", :franchise)
    view |> element("#analytics-confirm-enable") |> render_click()
    assert Features.enabled?("analytics_funnel", {:branch, target.id})
    assert Features.enabled?("analytics_funnel", {:branch, other.id})
    assert Features.enabled?("analytics_funnel", {:branch, third.id})
  end

  test "network controls enable the network and selected branches", %{conn: conn} do
    branch = insert(:branch)
    {conn, _} = login(conn, ["admin"])
    {:ok, view, _} = live(conn, ~p"/staff/franchise/analytics")
    view |> element("#analytics-toggle-0") |> render_click()
    assert Features.enabled?("analytics_franchise", :franchise)
    assert Features.enabled?("analytics_extended", :franchise)
    refute Features.enabled?("analytics_franchise", {:branch, branch.id})
    view |> element("#analytics-toggle-1") |> render_click()
    assert Features.enabled?("analytics_franchise", {:branch, branch.id})
    assert Features.enabled?("analytics_extended", {:branch, branch.id})
  end
end
