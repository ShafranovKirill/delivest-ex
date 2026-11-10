defmodule DelivestWeb.Staff.SegmentLive.IndexTest do
  use DelivestWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Ecto.Query

  alias Delivest.{Features, Repo, Segments}
  alias Delivest.Segments.Segment

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

  test "an open settings form cannot save after feature is disabled", %{
    conn: conn,
    branch: branch
  } do
    enable(branch)
    {:ok, view, _} = live(conn, ~p"/staff/segments/new")
    {:ok, _} = Features.configure("segments", :franchise, false, actor: "test")

    view
    |> form("#segment-settings-form",
      segment: %{name: "Blocked", kind: "manual", scope: "branches"}
    )
    |> render_submit()

    assert_redirect(view, ~p"/staff/branches/select")
    refute Repo.exists?(from s in Segment, where: s.name == "Blocked")
  end

  test "manual creation is empty and clients are added only from its tab", %{
    conn: conn,
    branch: branch,
    staff: staff
  } do
    enable(branch)
    staff = grant_network(staff)
    client = insert(:client, name: "Test Guest")
    {:ok, view, _} = live(conn, ~p"/staff/segments/new")
    refute has_element?(view, "#segment-client-picker")

    view
    |> form("#segment-settings-form",
      segment: %{name: "Manual group", kind: "manual", scope: "franchise"}
    )
    |> render_submit()

    assert has_element?(view, "#segment-review-panel", "Добавьте клиентов после сохранения")
    view |> element("#segment-save") |> render_click()
    assert_redirect(view)
    group = Repo.get_by!(Segment, name: "Manual group")
    assert {:ok, []} = Segments.list_members(staff, group.id)

    {:ok, detail, _} = live(conn, ~p"/staff/segments/#{group.id}")
    refute has_element?(detail, "#segment-clients")
    detail |> element("a[role='tab']", "Клиенты") |> render_click()
    assert has_element?(detail, "#segment-clients")
    detail |> element("a", "Добавить клиентов") |> render_click()
    detail |> form("#segment-client-search", filter: %{search: "Test Guest"}) |> render_submit()
    assert has_element?(detail, "#client-row-#{client.id}")
    detail |> element("#client-row-#{client.id} button") |> render_click()
    refute has_element?(detail, "#client-row-#{client.id}")
    detail |> element("a", "В сегменте") |> render_click()
    assert has_element?(detail, "#client-row-#{client.id}")
    detail |> element("#client-row-#{client.id} button") |> render_click()
    refute has_element?(detail, "#client-row-#{client.id}")
    assert {:ok, []} = Segments.list_members(staff, group.id)
  end

  test "single settings form includes a pending condition on review", %{
    conn: conn,
    branch: branch
  } do
    enable(branch)
    {:ok, view, _} = live(conn, ~p"/staff/segments/new")

    view
    |> form("#segment-settings-form",
      segment: %{name: "Frequent guests", kind: "dynamic", scope: "branches"}
    )
    |> render_change()

    view |> element("#branch-#{branch.id}") |> render_click()

    view
    |> form("#segment-settings-form",
      segment: %{name: "Frequent guests", kind: "dynamic", scope: "branches", match: "all"},
      condition: %{metric: "order_count", op: "gte", value: "2"}
    )
    |> render_submit()

    assert has_element?(view, "#segment-review-panel", "Количество заказов не меньше 2")
    view |> element("#segment-save") |> render_click()
    assert_redirect(view)

    assert %{"conditions" => [%{"value" => 2}]} =
             Repo.get_by!(Segment, name: "Frequent guests").rules
  end

  test "invalid pending condition blocks review even if another was added", %{
    conn: conn,
    branch: branch
  } do
    enable(branch)
    {:ok, view, _} = live(conn, ~p"/staff/segments/new")

    view
    |> form("#segment-settings-form",
      segment: %{name: "Invalid", kind: "dynamic", scope: "branches"}
    )
    |> render_change()

    view |> element("#branch-#{branch.id}") |> render_click()

    view
    |> form("#segment-settings-form",
      segment: %{name: "Invalid", kind: "dynamic", scope: "branches"},
      condition: %{metric: "order_count", op: "gte", value: "2"}
    )
    |> render_change()

    view |> element("button[phx-click='add_condition']") |> render_click()

    assert has_element?(view, "#condition-0")

    view
    |> form("#segment-settings-form",
      segment: %{name: "Invalid", kind: "dynamic", scope: "branches"},
      condition: %{metric: "order_count", op: "gte", value: "-1"}
    )
    |> render_submit()

    assert has_element?(view, "#condition-error", "Введите целое неотрицательное число")
    refute has_element?(view, "#segment-review-panel")
  end

  test "explicit add does not duplicate a condition on review", %{conn: conn, branch: branch} do
    enable(branch)
    {:ok, view, _} = live(conn, ~p"/staff/segments/new")

    view
    |> form("#segment-settings-form",
      segment: %{name: "Once", kind: "dynamic", scope: "branches"}
    )
    |> render_change()

    view |> element("#branch-#{branch.id}") |> render_click()

    view
    |> form("#segment-settings-form",
      segment: %{name: "Once", kind: "dynamic", scope: "branches"},
      condition: %{metric: "order_count", op: "gte", value: "2"}
    )
    |> render_change()

    view |> element("button[phx-click='add_condition']") |> render_click()

    assert has_element?(view, "#condition-0")

    view
    |> form("#segment-settings-form",
      segment: %{name: "Once", kind: "dynamic", scope: "branches"}
    )
    |> render_submit()

    view |> element("#segment-save") |> render_click()
    assert_redirect(view)
    assert %{"conditions" => [_]} = Repo.get_by!(Segment, name: "Once").rules
  end

  test "edit changes name and match while keeping type and scope", %{
    conn: conn,
    branch: branch,
    staff: staff
  } do
    enable(branch)

    rules = %{
      "version" => 1,
      "match" => "all",
      "conditions" => [%{"metric" => "order_count", "op" => "gte", "value" => 2}]
    }

    {:ok, group} =
      Segments.create(staff, %{name: "Before", kind: :dynamic, scope: :branches, rules: rules}, [
        branch.id
      ])

    {:ok, view, _} = live(conn, ~p"/staff/segments/#{group.id}/edit")
    refute has_element?(view, "#segment-settings-form [name='segment[kind]']")
    refute has_element?(view, "#segment-settings-form [name='segment[scope]']")

    view
    |> form("#segment-settings-form", segment: %{name: "After", match: "any"})
    |> render_submit()

    view |> element("#segment-save") |> render_click()
    assert_redirect(view)
    updated = Repo.get!(Segment, group.id)
    assert updated.name == "After"
    assert updated.kind == :dynamic and updated.scope == :branches
    assert updated.rules["match"] == "any"
  end

  test "overview does not query membership until clients tab opens", %{
    conn: conn,
    branch: branch,
    staff: staff
  } do
    enable(branch)
    staff = grant_network(staff)
    {:ok, group} = Segments.create(staff, %{name: "Lazy", kind: :manual, scope: :franchise})
    id = "segment-lazy-#{System.unique_integer([:positive])}"
    pid = self()

    :ok =
      :telemetry.attach(
        id,
        [:delivest, :repo, :query],
        fn _, _, metadata, _ ->
          if String.contains?(metadata.query, "segment_manual_members"),
            do: send(pid, {:membership_query, id})
        end,
        nil
      )

    try do
      {:ok, view, _} = live(conn, ~p"/staff/segments/#{group.id}")
      assert has_element?(view, "#segment-edit-link", "Изменить")
      refute has_element?(view, "#segment-settings")
      refute has_element?(view, "#segment-clients")
      refute_received {:membership_query, ^id}

      view |> element("a[role='tab']", "Параметры") |> render_click()
      assert has_element?(view, "#segment-settings")
      refute_received {:membership_query, ^id}

      view |> element("a[role='tab']", "Параметры") |> render_click()
      refute has_element?(view, "#segment-settings")
      refute_received {:membership_query, ^id}

      view |> element("a[role='tab']", "Клиенты") |> render_click()
      assert_received {:membership_query, ^id}
      assert has_element?(view, "#segment-clients")
      drain_membership_queries(id)

      view |> element("a[role='tab']", "Клиенты") |> render_click()
      refute has_element?(view, "#segment-clients")
      refute has_element?(view, "#segment-settings")
      refute_received {:membership_query, ^id}
    after
      :telemetry.detach(id)
    end
  end

  test "long client search reports an error in the current tab", %{
    conn: conn,
    branch: branch,
    staff: staff
  } do
    enable(branch)
    staff = grant_network(staff)
    {:ok, group} = Segments.create(staff, %{name: "Search", kind: :manual, scope: :franchise})
    {:ok, view, _} = live(conn, ~p"/staff/segments/#{group.id}?tab=clients")
    assert has_element?(view, "#segment-client-search input[maxlength='100']")
    render_hook(view, "client_search", %{"filter" => %{"search" => String.duplicate("x", 101)}})
    assert has_element?(view, "#segment-clients [role='alert']", "не больше 100 символов")
    assert has_element?(view, "#segment-clients")
  end

  test "client table pages, sorts, and resets page on search", %{
    conn: conn,
    branch: branch,
    staff: staff
  } do
    enable(branch)
    staff = grant_network(staff)

    clients =
      for i <- 1..21,
          do: insert(:client, name: "Guest #{String.pad_leading(to_string(i), 2, "0")}")

    {:ok, group} =
      Segments.create(
        staff,
        %{name: "Large group", kind: :manual, scope: :franchise},
        [],
        Enum.map(clients, & &1.id)
      )

    {:ok, view, _} = live(conn, ~p"/staff/segments/#{group.id}")
    refute has_element?(view, "#segment-client-rows")
    view |> element("a[role='tab']", "Клиенты") |> render_click()
    assert length(Regex.scan(~r/id="client-row-[^"]+"/, render(view))) == 20
    assert has_element?(view, "#segment-clients", "Страница 1 из 2")

    view
    |> element(
      "#segment-clients-pagination-top button[phx-click='client_page'][phx-value-page='2']"
    )
    |> render_click()

    assert length(Regex.scan(~r/id="client-row-[^"]+"/, render(view))) == 1
    view |> element("button[phx-click='client_sort'][phx-value-field='phone']") |> render_click()
    assert has_element?(view, "#segment-clients", "Страница 1 из 2")
    view |> form("#segment-client-search", filter: %{search: "Guest 21"}) |> render_submit()
    assert has_element?(view, "#client-row-#{Enum.at(clients, 20).id}")
    assert has_element?(view, "#segment-clients", "Страница 1 из 1")
  end

  test "dynamic and read-only clients cannot open available mode or mutate", %{
    conn: conn,
    branch: branch,
    staff: staff
  } do
    enable(branch)
    staff = grant_network(staff)

    rules = %{
      "version" => 1,
      "match" => "all",
      "conditions" => [%{"metric" => "order_count", "op" => "gte", "value" => 1}]
    }

    {:ok, group} =
      Segments.create(staff, %{name: "Dynamic", kind: :dynamic, scope: :franchise, rules: rules})

    {:ok, view, _} = live(conn, ~p"/staff/segments/#{group.id}?tab=clients")
    refute has_element?(view, "a", "Добавить клиентов")
    refute has_element?(view, "#segment-client-rows button[phx-click='add_member']")

    {:ok, manual} = Segments.create(staff, %{name: "Read only", kind: :manual, scope: :franchise})

    readonly =
      insert(:staff, role: insert(:role, permissions: ["segments.read", "segments.network"]))

    readonly_conn = init_test_session(conn, %{"staff_id" => readonly.id})
    {:ok, readonly_view, _} = live(readonly_conn, ~p"/staff/segments/#{manual.id}?tab=clients")
    refute has_element?(readonly_view, "#segment-edit-link")
    refute has_element?(readonly_view, "a", "Добавить клиентов")
    refute has_element?(readonly_view, "#segment-client-rows button")
  end

  test "dynamic detail starts a background recalculation and read-only staff cannot start one",
       ctx do
    enable(ctx.branch)

    rules = %{
      "version" => 1,
      "match" => "all",
      "conditions" => [%{"metric" => "order_count", "op" => "gte", "value" => 1}]
    }

    {:ok, group} =
      Segments.create(
        ctx.staff,
        %{name: "Now", kind: :dynamic, scope: :branches, rules: rules},
        [ctx.branch.id]
      )

    {:ok, view, _} = live(ctx.conn, ~p"/staff/segments/#{group.id}?tab=settings")
    assert has_element?(view, "#segment-recalculate-now")
    assert has_element?(view, "#segment-calculation-status")
    assert has_element?(view, "#segment-recalculate-now", "Проверить расчёт")
    old_token = :sys.get_state(view.pid).socket.assigns.poll_token
    view |> element("#segment-recalculate-now") |> render_click()
    refute :sys.get_state(view.pid).socket.assigns.poll_token == old_token
    assert has_element?(view, "#segment-calculation-status")

    readonly = insert(:staff, role: insert(:role, permissions: ["segments.read"]))
    insert(:staff_branch, staff: readonly, branch: ctx.branch)
    conn = init_test_session(ctx.conn, %{"staff_id" => readonly.id})
    {:ok, readonly_view, _} = live(conn, ~p"/staff/segments/#{group.id}?tab=settings")
    refute has_element?(readonly_view, "#segment-recalculate-now")
    render_hook(readonly_view, "recalculate_segment", %{})
    refute has_element?(readonly_view, "#segment-recalculate-now")
  end

  defp enable(branch) do
    {:ok, _} = Features.configure("segments", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("segments", {:branch, branch.id}, true, actor: "test")
  end

  defp grant_network(staff) do
    staff = Repo.preload(staff, :role)

    Repo.update!(
      Ecto.Changeset.change(staff.role,
        permissions: ["segments.read", "segments.manage", "segments.network"]
      )
    )

    Repo.preload(staff, :role, force: true)
  end

  defp drain_membership_queries(id) do
    receive do
      {:membership_query, ^id} -> drain_membership_queries(id)
    after
      0 -> :ok
    end
  end
end
