defmodule DelivestWeb.Staff.SegmentLive.IndexTest do
  use DelivestWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Ecto.Query

  alias Delivest.{Features, Repo}
  alias Delivest.Segments.Segment
  alias Delivest.Segments

  setup %{conn: conn} do
    branch = insert(:branch, is_active: true)
    staff = insert(:staff, role: insert(:role, permissions: ["segments.read", "segments.manage"]))
    Repo.insert!(%Delivest.Identity.StaffBranch{staff_id: staff.id, branch_id: branch.id})
    %{conn: init_test_session(conn, %{"staff_id" => staff.id}), branch: branch, staff: staff}
  end

  test "disabled feature redirects direct route", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/staff/branches/select"}}} =
             live(conn, ~p"/staff/segments")
  end

  test "branch staff sees no segment entry when only the parent gate is enabled", %{
    conn: conn,
    staff: staff
  } do
    {:ok, _} = Features.configure("segments", :franchise, true, actor: "test")
    pages = DelivestWeb.StaffNav.pages(Repo.preload(staff, [:role, :branches]), nil)
    refute Enum.any?(pages, &(&1.page == :segments))

    assert {:error, {:redirect, %{to: "/staff/branches/select"}}} =
             live(conn, ~p"/staff/segments")
  end

  test "an already open wizard cannot save after the parent gate is disabled", %{
    conn: conn,
    branch: branch
  } do
    enable(branch)
    {:ok, view, _} = live(conn, ~p"/staff/segments/new")
    {:ok, _} = Features.configure("segments", :franchise, false, actor: "test")

    view
    |> form("#segment-details-form",
      segment: %{name: "Blocked", kind: "manual", scope: "branches"}
    )
    |> render_submit()

    assert_redirect(view, ~p"/staff/branches/select")
    refute Repo.exists?(from s in Segment, where: s.name == "Blocked")
  end

  test "manual wizard creates a branch segment", %{conn: conn, branch: branch} do
    enable(branch)
    {:ok, view, _} = live(conn, ~p"/staff/segments/new")
    assert has_element?(view, "#segment-details-form")

    view
    |> form("#segment-details-form",
      segment: %{name: "VIP guests", kind: "manual", scope: "branches"}
    )
    |> render_submit()

    view |> element("#branch-#{branch.id}") |> render_click()
    view |> element("#segment-review") |> render_click()
    assert has_element?(view, "#segment-review-panel")
    view |> element("#segment-save") |> render_click()
    assert_redirect(view)
    assert Repo.get_by!(Segment, name: "VIP guests").scope == :branches
  end

  test "dynamic wizard saves validated conditions", %{conn: conn, branch: branch} do
    enable(branch)
    {:ok, view, _} = live(conn, ~p"/staff/segments/new")

    view
    |> form("#segment-details-form",
      segment: %{name: "Frequent guests", kind: "dynamic", scope: "branches"}
    )
    |> render_submit()

    view |> element("#branch-#{branch.id}") |> render_click()

    view
    |> form("#segment-condition-form", condition: %{metric: "order_count", op: "gte", value: "2"})
    |> render_submit()

    assert has_element?(view, "#condition-0")
    view |> element("#segment-review") |> render_click()
    view |> element("#segment-save") |> render_click()
    assert_redirect(view)

    assert %{"conditions" => [%{"value" => 2}]} =
             Repo.get_by!(Segment, name: "Frequent guests").rules
  end

  test "edit wizard updates name and conditions with immutable scope", %{
    conn: conn,
    branch: branch,
    staff: staff
  } do
    enable(branch)

    rules = %{
      "version" => 1,
      "match" => "all",
      "conditions" => [
        %{"metric" => "order_count", "op" => "gte", "value" => 2}
      ]
    }

    {:ok, group} =
      Segments.create(staff, %{name: "Before", kind: :dynamic, scope: :branches, rules: rules}, [
        branch.id
      ])

    {:ok, view, _} = live(conn, ~p"/staff/segments/#{group.id}/edit")
    assert has_element?(view, "#segment-details-form")
    view |> form("#segment-details-form", segment: %{name: "After"}) |> render_submit()
    view |> element("#segment-review") |> render_click()
    view |> element("#segment-save") |> render_click()
    assert_redirect(view)
    updated = Repo.get!(Segment, group.id)
    assert updated.name == "After"
    assert updated.kind == :dynamic and updated.scope == :branches
  end

  test "member pagination continues after a full second page", %{conn: conn, staff: staff} do
    {:ok, _} = Features.configure("segments", :franchise, true, actor: "test")
    admin = Repo.preload(staff, :role)
    Repo.update!(Ecto.Changeset.change(admin.role, permissions: ["admin"]))
    admin = Repo.preload(admin, :role, force: true)

    {:ok, group} =
      Segments.create(admin, %{name: "Large group", kind: :manual, scope: :franchise})

    clients = for _ <- 1..101, do: insert(:client)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.insert_all(
      "segment_manual_members",
      Enum.map(clients, fn client ->
        %{
          segment_id: Ecto.UUID.dump!(group.id),
          client_id: Ecto.UUID.dump!(client.id),
          inserted_at: now,
          updated_at: now
        }
      end)
    )

    {:ok, view, _} = live(conn, ~p"/staff/segments/#{group.id}")
    assert has_element?(view, "#segment-members button[phx-click='more_members']")
    view |> element("#segment-members button[phx-click='more_members']") |> render_click()
    assert has_element?(view, "#segment-members button[phx-click='more_members']")
    view |> element("#segment-members button[phx-click='more_members']") |> render_click()
    refute has_element?(view, "#segment-members button[phx-click='more_members']")
    last = Enum.max_by(clients, & &1.id)
    assert has_element?(view, "#member-#{last.id}")
  end

  defp enable(branch) do
    {:ok, _} = Features.configure("segments", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("segments", {:branch, branch.id}, true, actor: "test")
  end
end
