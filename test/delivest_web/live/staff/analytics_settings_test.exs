defmodule DelivestWeb.Staff.AnalyticsSettingsTest do
  use DelivestWeb.ConnCase, async: false

  import Delivest.Factory
  import Phoenix.LiveViewTest

  alias Delivest.{Features, Repo}

  defp login(conn, permissions) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    {init_test_session(conn, %{"staff_id" => staff.id}), staff}
  end

  test "administrator can enable and confirm disabling branch tracking centrally", %{conn: conn} do
    branch = insert(:branch)
    {conn, _} = login(conn, ["admin"])
    {:ok, view, _} = live(conn, ~p"/staff/settings?#{%{branch: branch.slug}}")
    assert has_element?(view, "#feature-toggle-analytics_funnel[aria-checked=false]")
    view |> element("#feature-toggle-analytics_funnel") |> render_click()
    assert Features.enabled?("analytics_funnel", {:branch, branch.id})
    assert has_element?(view, "#feature-toggle-analytics_funnel[aria-checked=true]")
    view |> element("#feature-toggle-analytics_funnel") |> render_click()
    assert has_element?(view, "#feature-confirmation[role=dialog][aria-modal=true]")
    assert has_element?(view, "#feature-confirmation[phx-key=escape]")
    assert has_element?(view, "#feature-confirmation-focus")
    assert has_element?(view, "#feature-cancel")
    assert Features.enabled?("analytics_funnel", {:branch, branch.id})
    view |> element("#feature-confirm") |> render_click()
    refute Features.enabled?("analytics_funnel", {:branch, branch.id})
    assert Features.enabled?("analytics_funnel", :franchise)
  end

  test "legacy analytics addresses redirect administrators to capabilities", %{conn: conn} do
    branch = insert(:branch)
    {conn, _} = login(conn, ["admin"])

    assert {:error, {:live_redirect, %{to: target}}} =
             live(conn, ~p"/staff/branches/#{branch.slug}/edit/analytics")

    assert target == "/staff/settings?branch=#{branch.slug}"

    assert {:error, {:live_redirect, %{to: "/staff/settings"}}} =
             live(conn, ~p"/staff/franchise/analytics")
  end

  test "branch editors cannot see disabled controls or change gates via forged events", %{
    conn: conn
  } do
    branch = insert(:branch)
    {conn, staff} = login(conn, ["branches.read", "branches.update", "franchise.update"])
    insert(:staff_branch, staff: staff, branch: branch)
    {:ok, view, _} = live(conn, ~p"/staff/settings?#{%{branch: branch.slug}}")
    refute has_element?(view, "#feature-analytics_funnel")
    view |> render_click("toggle", %{"feature" => "analytics_funnel"})
    refute Features.enabled?("analytics_funnel", :franchise)
    refute has_element?(view, "#feature-toggle-analytics_funnel")

    assert {:error, {:live_redirect, _}} =
             live(conn, ~p"/staff/branches/#{branch.slug}/edit/analytics")
  end

  test "forged keys and revoked administrator cannot change features", %{conn: conn} do
    branch = insert(:branch)
    {conn, staff} = login(conn, ["admin"])
    {:ok, view, _} = live(conn, ~p"/staff/settings?#{%{branch: branch.slug}}")
    view |> render_click("toggle", %{"feature" => "not_a_feature"})
    refute Features.enabled?("yandex_ads", :franchise)

    staff.role
    |> Ecto.Changeset.change(permissions: ["branches.read", "branches.update"])
    |> Repo.update!()

    view |> render_click("toggle", %{"feature" => "analytics_funnel"})
    refute Features.enabled?("analytics_funnel", :franchise)
    refute has_element?(view, "#feature-toggle-analytics_funnel")
  end

  test "enabling a dormant network function confirms all affected branches and rejects stale confirmation",
       %{conn: conn} do
    other = insert(:branch, name: "Previously enabled branch")
    third = insert(:branch)
    {conn, _} = login(conn, ["admin"])
    {:ok, _} = Features.configure("analytics_funnel", {:branch, other.id}, true, actor: "host")
    {:ok, view, _} = live(conn, ~p"/staff/settings")
    view |> element("#feature-toggle-analytics_funnel") |> render_click()
    assert has_element?(view, "#feature-confirmation", other.name)
    refute Features.enabled?("analytics_funnel", :franchise)

    {:ok, _} = Features.configure("analytics_funnel", {:branch, third.id}, true, actor: "host")
    view |> element("#feature-confirm") |> render_click()
    assert has_element?(view, "#feature-confirmation", third.name)
    refute Features.enabled?("analytics_funnel", :franchise)
    view |> element("#feature-confirm") |> render_click()
    assert Features.enabled?("analytics_funnel", {:branch, other.id})
    assert Features.enabled?("analytics_funnel", {:branch, third.id})
  end
end
