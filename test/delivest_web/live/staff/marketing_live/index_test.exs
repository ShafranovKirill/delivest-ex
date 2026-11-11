defmodule DelivestWeb.Staff.MarketingLive.IndexTest do
  use DelivestWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.{Features, Marketing, Repo, Segments}
  alias Delivest.OrderFixtures

  setup %{conn: conn} do
    branch = insert(:branch, is_active: true)

    staff =
      insert(:staff,
        role:
          insert(:role,
            permissions:
              ~w(segments.read segments.manage marketing.read marketing.manage marketing.reports)
          )
      )

    insert(:staff_branch, staff: staff, branch: branch)
    %{conn: init_test_session(conn, %{"staff_id" => staff.id}), branch: branch, staff: staff}
  end

  test "feature gate hides policy screen", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/staff/branches/select"}}} =
             live(conn, ~p"/staff/marketing/policies")
  end

  test "wizard creates a draft with branch scope and async preview", ctx do
    {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "test")

    {:ok, _} =
      Features.configure("marketing_policies", {:branch, ctx.branch.id}, true, actor: "test")

    {:ok, segment} =
      Segments.create(ctx.staff, %{name: "VIP audience", kind: :manual, scope: :branches}, [
        ctx.branch.id
      ])

    promotion =
      insert_promotion(ctx.branch.id,
        kind: :personal_code,
        rules: "then discount 10%"
      )

    {:ok, view, _} = live(ctx.conn, ~p"/staff/marketing/new")
    assert has_element?(view, "#marketing-policy-audience")
    assert has_element?(view, "#marketing-policy-wizard", "Step 1 of 5")

    view
    |> element("button[phx-click='toggle_branch'][phx-value-id='#{ctx.branch.id}']")
    |> render_click()

    view
    |> form("#marketing-policy-audience",
      policy: %{
        name: "VIP return",
        scope: "branches",
        segment_id: segment.id
      }
    )
    |> render_submit()

    assert has_element?(view, "#marketing-policy-reward")

    view
    |> form("#marketing-policy-reward", policy: %{reward_branch_id: ctx.branch.id})
    |> render_change()

    view
    |> form("#marketing-policy-reward",
      policy: %{reward_branch_id: ctx.branch.id, promotion_id: promotion.id}
    )
    |> render_submit()

    assert has_element?(view, "#marketing-policy-message")

    view
    |> form("#marketing-policy-message",
      policy: %{
        message_title: "Return",
        message_body: "Your offer is ready"
      }
    )
    |> render_submit()

    assert has_element?(view, "#marketing-policy-limits")
    assert has_element?(view, "#marketing-exclusions", "No customers excluded")
    assert has_element?(view, "#marketing-exclusions", "No groups excluded")

    view
    |> form("#marketing-policy-limits",
      policy: %{
        inactivity_days: "30",
        reward_ttl_days: "14",
        attribution_days: "7",
        initial_mode: "future_only"
      }
    )
    |> render_submit()

    assert has_element?(view, "#marketing-policy-review")
    assert has_element?(view, "#marketing-policy-review", "VIP audience")
    view |> element("#marketing-policy-review button[phx-click='back']") |> render_click()
    assert has_element?(view, "#marketing-policy-limits")
    view |> form("#marketing-policy-limits", policy: %{}) |> render_submit()
    view |> element("#marketing-save") |> render_click()

    assert_redirect(view)
    {:ok, [policy]} = Marketing.list(Repo.preload(ctx.staff, [:role, :branches]))
    assert policy.name == "VIP return"
    assert policy.status == :draft

    {:ok, detail, _} = live(ctx.conn, ~p"/staff/marketing/#{policy.id}")
    assert has_element?(detail, "#marketing-preview")
    detail |> element("#marketing-preview") |> render_click()
    assert has_element?(detail, "#marketing-preview-result")
  end

  test "wizard and policy list use Russian labels", ctx do
    {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "test")
    conn = init_test_session(ctx.conn, %{"locale" => "ru"})

    {:ok, index, _} = live(conn, ~p"/staff/marketing/policies")
    assert render(element(index, "#staff-page-header")) =~ "Маркетинговые политики"

    assert DelivestWeb.PortalTestHelper.has_element?(
             index,
             "#staff-page-header-actions",
             "a",
             "Новая политика"
           )

    {:ok, view, _} = live(conn, ~p"/staff/marketing/new")
    assert has_element?(view, "#marketing-policy-wizard", "Шаг 1 из 5")
    assert has_element?(view, "#marketing-policy-audience", "Аудитория")
    refute has_element?(view, "#marketing-more-segments")
  end

  test "global reward calculation is explicit and requires network permission", ctx do
    enable_marketing(ctx)
    {:ok, ordinary, _} = live(ctx.conn, ~p"/staff/marketing/policies")

    refute DelivestWeb.PortalTestHelper.has_element?(
             ordinary,
             "#staff-page-header-actions",
             "#marketing-recalculate-now"
           )

    render_hook(ordinary, "recalculate_marketing", %{})
    refute has_element?(ordinary, "#marketing-calculation-status")

    network_staff =
      insert(:staff,
        role:
          insert(:role,
            permissions: ~w(marketing.read marketing.manage marketing.network marketing.reports)
          )
      )

    insert(:staff_branch, staff: network_staff, branch: ctx.branch)

    network_conn =
      init_test_session(ctx.conn, %{"staff_id" => network_staff.id, "locale" => "ru"})

    {:ok, network, _} = live(network_conn, ~p"/staff/marketing/policies")

    assert DelivestWeb.PortalTestHelper.has_element?(
             network,
             "#staff-page-header-actions",
             "#marketing-recalculate-now"
           )

    assert has_element?(network, "#marketing-calculation-panel", "выдаст положенные награды")
    render_click(network, "recalculate_marketing")
    assert has_element?(network, "#marketing-calculation-status")

    assert DelivestWeb.PortalTestHelper.has_element?(
             network,
             "#staff-page-header-actions",
             "#marketing-recalculate-now"
           )
  end

  test "completed global calculation refreshes issued counts in the current policy list", ctx do
    {_staff, policy} = policy_fixture(ctx, "Fresh issue count")

    network_staff =
      insert(:staff,
        role:
          insert(:role,
            permissions: ~w(marketing.read marketing.manage marketing.network marketing.reports)
          )
      )

    insert(:staff_branch, staff: network_staff, branch: ctx.branch)
    conn = init_test_session(ctx.conn, %{"staff_id" => network_staff.id})
    {:ok, view, _} = live(conn, ~p"/staff/marketing/policies")
    assert has_element?(view, "#marketing-policies", "0 issues")
    render_click(view, "recalculate_marketing")

    token = :sys.get_state(view.pid).socket.assigns.poll_tokens.calculation
    assert token

    Repo.query!("UPDATE marketing_policies SET issued_count=7 WHERE id=$1", [
      Ecto.UUID.dump!(policy.id)
    ])

    Repo.query!(
      "UPDATE background_schedules SET running=false, current_job_id=NULL, rerun_requested=false, next_at=now() + interval '1 hour', last_success_at=now() WHERE kind='marketing.evaluate' AND scope_key='franchise'"
    )

    send(view.pid, {:marketing_poll, :calculation, token, nil})
    _ = :sys.get_state(view.pid)
    assert has_element?(view, "#marketing-calculation-status", "Calculation completed")
    assert has_element?(view, "#marketing-policies", "7 issues")
  end

  test "pending preview becomes ready from a read-only poll without another request", ctx do
    {_staff, policy} = policy_fixture(ctx, "Preview poll")
    {:ok, view, _} = live(ctx.conn, ~p"/staff/marketing/#{policy.id}")
    view |> element("#marketing-preview") |> render_click()
    assert has_element?(view, "#marketing-preview", "Check calculation")

    [[request_id]] =
      Repo.query!("SELECT request_id FROM marketing_previews WHERE policy_id=$1", [
        Ecto.UUID.dump!(policy.id)
      ]).rows

    view |> element("#marketing-preview") |> render_click()

    [[coalesced_request_id]] =
      Repo.query!("SELECT request_id FROM marketing_previews WHERE policy_id=$1", [
        Ecto.UUID.dump!(policy.id)
      ]).rows

    assert coalesced_request_id == request_id

    Repo.query!(
      "UPDATE marketing_previews SET status='ready', eligible_count=2, completed_at=now() WHERE policy_id=$1",
      [Ecto.UUID.dump!(policy.id)]
    )

    token = :sys.get_state(view.pid).socket.assigns.poll_tokens.preview
    send(view.pid, {:marketing_poll, :preview, token, policy.id})
    _ = :sys.get_state(view.pid)
    assert has_element?(view, "#marketing-preview-result", "Eligible customers: 2")
    assert has_element?(view, "#marketing-preview", "Calculate audience now")

    [[same_request_id]] =
      Repo.query!("SELECT request_id FROM marketing_previews WHERE policy_id=$1", [
        Ecto.UUID.dump!(policy.id)
      ]).rows

    assert same_request_id == request_id
  end

  test "pending report updates via scoped status read and ignores poll after panel closes", ctx do
    {_staff, policy} = policy_fixture(ctx, "Report poll")
    {:ok, view, _} = live(ctx.conn, ~p"/staff/marketing/#{policy.id}")
    view |> element("#marketing-report-toggle") |> render_click()
    view |> form("#marketing-report-form", report: %{}) |> render_submit()
    assert has_element?(view, "#marketing-report-pending")

    state = :sys.get_state(view.pid).socket.assigns
    report_id = state.report.id

    view |> element("#marketing-report-recalculate-now") |> render_click()
    assert :sys.get_state(view.pid).socket.assigns.report.id == report_id
    token = :sys.get_state(view.pid).socket.assigns.poll_tokens.report

    Repo.query!(
      "UPDATE marketing_report_requests SET status='ready', phase='orders', as_of=now(), data=$2::jsonb WHERE id=$1",
      [Ecto.UUID.dump!(report_id), Jason.encode!(%{"issued" => 3, "series" => []})]
    )

    send(view.pid, {:marketing_poll, :report, token, policy.id})
    _ = :sys.get_state(view.pid)
    assert has_element?(view, "#marketing-report-result", "Issues: 3")

    view |> element("#marketing-report-toggle") |> render_click()
    send(view.pid, {:marketing_poll, :report, token, policy.id})
    _ = :sys.get_state(view.pid)
    refute has_element?(view, "#marketing-report-panel")
  end

  test "comparison waits for member reports and then polls its own result", ctx do
    {_staff, policy} = policy_fixture(ctx, "Comparison poll")
    {:ok, view, _} = live(ctx.conn, ~p"/staff/marketing/#{policy.id}")
    view |> element("#marketing-report-toggle") |> render_click()
    view |> element("#marketing-compare-run") |> render_click()
    assert has_element?(view, "#marketing-compare-pending")

    comparison = :sys.get_state(view.pid).socket.assigns.comparison
    assert comparison[:id] == nil
    policy_id = policy.id
    assert [%{policy_id: ^policy_id, request_id: request_id}] = comparison.rows

    Repo.query!(
      "UPDATE marketing_report_requests SET status='ready', phase='orders', as_of=now(), data=$2::jsonb WHERE id=$1",
      [Ecto.UUID.dump!(request_id), Jason.encode!(%{"issued" => 1, "series" => []})]
    )

    token = :sys.get_state(view.pid).socket.assigns.poll_tokens.comparison
    send(view.pid, {:marketing_poll, :comparison, token, policy.id})
    state = :sys.get_state(view.pid).socket.assigns
    assert state.comparison.id
    assert state.comparison.status == :pending

    Repo.query!(
      "UPDATE marketing_report_comparisons SET status='ready', as_of=now(), data=$2::jsonb WHERE id=$1",
      [
        Ecto.UUID.dump!(state.comparison.id),
        Jason.encode!(%{
          "linked_orders" => 1,
          "linked_net_revenue" => 10_000,
          "series" => [],
          "return_branches" => []
        })
      ]
    )

    send(view.pid, {:marketing_poll, :comparison, token, policy.id})
    _ = :sys.get_state(view.pid)
    assert has_element?(view, "#marketing-compare-result", "Linked orders: 1")
  end

  test "old comparison poll cannot start work after navigating to another policy", ctx do
    {_staff, first} = policy_fixture(ctx, "Old comparison")
    {_staff, second} = policy_fixture(ctx, "New comparison")
    {:ok, view, _} = live(ctx.conn, ~p"/staff/marketing/#{first.id}")
    view |> element("#marketing-report-toggle") |> render_click()
    view |> element("#marketing-compare-run") |> render_click()

    state = :sys.get_state(view.pid).socket.assigns
    token = state.poll_tokens.comparison
    assert [%{request_id: request_id}] = state.comparison.rows

    Repo.query!(
      "UPDATE marketing_report_requests SET status='ready', phase='orders', as_of=now(), data=$2::jsonb WHERE id=$1",
      [Ecto.UUID.dump!(request_id), Jason.encode!(%{"issued" => 1, "series" => []})]
    )

    render_patch(view, ~p"/staff/marketing/#{second.id}")
    send(view.pid, {:marketing_poll, :comparison, token, first.id})
    state = :sys.get_state(view.pid).socket.assigns

    assert state.policy.id == second.id
    assert state.comparison == nil
    assert state.poll_tokens == %{}
    assert state.poll_deadlines == %{}
    assert state.poll_counts == %{}
    assert [[0]] = Repo.query!("SELECT count(*) FROM marketing_report_comparisons").rows
  end

  test "back keeps changed audience, message and limits fields", ctx do
    enable_marketing(ctx)
    {:ok, view, _} = live(ctx.conn, ~p"/staff/marketing/new")

    view
    |> form("#marketing-policy-audience", policy: %{name: "Changed audience"})
    |> render_change()

    view |> form("#marketing-policy-audience", policy: %{}) |> render_submit()
    view |> element("#marketing-policy-reward button[phx-click='back']") |> render_click()
    assert has_element?(view, "#marketing-policy-audience input[value='Changed audience']")

    view |> form("#marketing-policy-audience", policy: %{}) |> render_submit()
    view |> form("#marketing-policy-reward", policy: %{}) |> render_submit()

    view
    |> form("#marketing-policy-message", policy: %{message_title: "Changed title"})
    |> render_change()

    view |> element("#marketing-policy-message button[phx-click='back']") |> render_click()
    view |> form("#marketing-policy-reward", policy: %{}) |> render_submit()
    assert has_element?(view, "#marketing-policy-message input[value='Changed title']")

    view |> form("#marketing-policy-message", policy: %{}) |> render_submit()

    view
    |> form("#marketing-policy-limits", policy: %{inactivity_days: "45"})
    |> render_change()

    view |> element("#marketing-policy-limits button[phx-click='back']") |> render_click()
    view |> form("#marketing-policy-message", policy: %{}) |> render_submit()
    assert has_element?(view, "#marketing-policy-limits input[value='45']")
  end

  test "editing a draft preserves excluded clients and segments", ctx do
    enable_marketing(ctx)
    staff = Repo.preload(ctx.staff, [:role, :branches])
    client = insert(:client)
    OrderFixtures.order_fixture(ctx.branch.id, attrs: %{"customer_phone" => client.phone})

    {:ok, audience} =
      Segments.create(staff, %{name: "Audience", kind: :manual, scope: :branches}, [
        ctx.branch.id
      ])

    {:ok, excluded} =
      Segments.create(staff, %{name: "Excluded", kind: :manual, scope: :branches}, [
        ctx.branch.id
      ])

    promotion =
      insert_promotion(ctx.branch.id, kind: :personal_code, rules: "then discount 10%")

    {:ok, policy} =
      Marketing.create(
        staff,
        %{
          "name" => "Original name",
          "scope" => "branches",
          "segment_id" => audience.id,
          "reward_branch_id" => ctx.branch.id,
          "promotion_id" => promotion.id,
          "inactivity_days" => 30,
          "reward_ttl_days" => 14,
          "attribution_days" => 7,
          "initial_mode" => "future_only",
          "channels" => ["in_app"],
          "message_title" => "Come back",
          "message_body" => "Your reward is ready"
        },
        [ctx.branch.id],
        [client.id],
        [excluded.id]
      )

    {:ok, view, _} = live(ctx.conn, ~p"/staff/marketing/#{policy.id}/edit")
    view |> form("#marketing-policy-audience", policy: %{name: "Updated name"}) |> render_submit()

    assert has_element?(
             view,
             "#marketing-policy-reward option[value='#{promotion.id}'][selected]"
           )

    view |> form("#marketing-policy-reward", policy: %{}) |> render_submit()
    view |> form("#marketing-policy-message", policy: %{}) |> render_submit()
    assert has_element?(view, "#marketing-excluded-clients button", client.phone)
    assert has_element?(view, "#marketing-excluded-segments button", excluded.name)
    refute has_element?(view, "#marketing-policy-limits textarea")
    view |> form("#marketing-policy-limits", policy: %{}) |> render_submit()
    view |> element("#marketing-save") |> render_click()

    assert_redirect(view)

    assert {:ok, %{client_ids: [client_id], segment_ids: [segment_id]}} =
             Marketing.exclusions(staff, policy.id)

    assert client_id == client.id
    assert segment_id == excluded.id
    assert {:ok, updated} = Marketing.get(staff, policy.id)
    assert updated.name == "Updated name"

    another_client = insert(:client)
    OrderFixtures.order_fixture(ctx.branch.id, attrs: %{"customer_phone" => another_client.phone})

    {:ok, another_group} =
      Segments.create(staff, %{name: "Another group", kind: :manual, scope: :branches}, [
        ctx.branch.id
      ])

    {:ok, edit, _} = live(ctx.conn, ~p"/staff/marketing/#{policy.id}/edit")
    edit |> form("#marketing-policy-audience", policy: %{}) |> render_submit()
    edit |> form("#marketing-policy-reward", policy: %{}) |> render_submit()
    edit |> form("#marketing-policy-message", policy: %{}) |> render_submit()

    edit
    |> form("#marketing-client-search", client_search: %{query: another_client.phone})
    |> render_submit()

    assert has_element?(edit, "#marketing-client-results button", another_client.phone)

    edit
    |> element("#marketing-client-results button[phx-value-id='#{another_client.id}']")
    |> render_click()

    assert has_element?(edit, "#marketing-excluded-clients button", another_client.phone)

    edit
    |> element("#marketing-excluded-clients button[phx-value-id='#{another_client.id}']")
    |> render_click()

    refute has_element?(
             edit,
             "#marketing-excluded-clients button[phx-value-id='#{another_client.id}']"
           )

    edit
    |> form("#marketing-segment-search", segment_search: %{query: "Another group"})
    |> render_submit()

    assert has_element?(edit, "#marketing-segment-results button", another_group.name)

    edit
    |> element("#marketing-segment-results button[phx-value-id='#{another_group.id}']")
    |> render_click()

    assert has_element?(edit, "#marketing-excluded-segments button", another_group.name)

    edit |> element("#marketing-policy-limits button[phx-click='back']") |> render_click()
    edit |> element("#marketing-policy-message button[phx-click='back']") |> render_click()
    edit |> element("#marketing-policy-reward button[phx-click='back']") |> render_click()

    edit
    |> form("#marketing-policy-audience", policy: %{segment_id: excluded.id})
    |> render_change()

    assert has_element?(edit, "#marketing-exclusions-reset")
    edit |> form("#marketing-policy-audience", policy: %{}) |> render_submit()
    edit |> form("#marketing-policy-reward", policy: %{}) |> render_submit()
    edit |> form("#marketing-policy-message", policy: %{}) |> render_submit()
    refute has_element?(edit, "#marketing-excluded-clients button")
    refute has_element?(edit, "#marketing-excluded-segments button")
  end

  test "searched promotion remains selectable after form changes and step navigation", ctx do
    enable_marketing(ctx)

    for index <- 1..50 do
      insert(:promotion,
        branch_id: ctx.branch.id,
        name: "A#{String.pad_leading(to_string(index), 2, "0")}",
        kind: :personal_code,
        rules: "then discount 10%"
      )
    end

    selected =
      insert(:promotion,
        branch_id: ctx.branch.id,
        name: "Z searched promotion",
        kind: :personal_code,
        rules: "then discount 10%"
      )

    {:ok, view, _} = live(ctx.conn, ~p"/staff/marketing/new")
    view |> form("#marketing-policy-audience", policy: %{}) |> render_submit()

    view
    |> form("#marketing-policy-reward", policy: %{reward_branch_id: ctx.branch.id})
    |> render_change()

    refute has_element?(view, "#marketing-policy-reward option[value='#{selected.id}']")

    view
    |> form("#marketing-promotion-search", promotion_search: %{query: "Z searched"})
    |> render_submit()

    assert has_element?(view, "#marketing-policy-reward option[value='#{selected.id}']")

    view
    |> form("#marketing-policy-reward", policy: %{promotion_id: selected.id})
    |> render_change()

    view |> form("#marketing-policy-reward", policy: %{}) |> render_submit()
    view |> element("#marketing-policy-message button[phx-click='back']") |> render_click()
    assert has_element?(view, "#marketing-policy-reward option[value='#{selected.id}'][selected]")

    view
    |> form("#marketing-policy-reward", policy: %{reward_branch_id: ""})
    |> render_change()

    refute has_element?(view, "#marketing-policy-reward option[value='#{selected.id}']")
  end

  test "comparison can select policies beyond the first page without losing earlier choices",
       ctx do
    enable_marketing(ctx)
    staff = Repo.preload(ctx.staff, [:role, :branches])

    {:ok, segment} =
      Segments.create(staff, %{name: "Comparison audience", kind: :manual, scope: :branches}, [
        ctx.branch.id
      ])

    promotion =
      insert_promotion(ctx.branch.id, kind: :personal_code, rules: "then discount 10%")

    policies =
      for index <- 1..52 do
        {:ok, policy} =
          Marketing.create(
            staff,
            policy_attrs("Comparison #{index}", segment.id, ctx.branch.id, promotion.id),
            [ctx.branch.id]
          )

        policy
      end
      |> Enum.sort_by(& &1.id)

    current = hd(policies)
    first_page_choice = Enum.at(policies, 1)
    later_choice = List.last(policies)

    hidden_branch = insert(:branch, is_active: true)

    hidden_staff =
      insert(:staff,
        role:
          insert(:role,
            permissions: ~w(segments.read segments.manage marketing.read marketing.manage)
          )
      )

    insert(:staff_branch, staff: hidden_staff, branch: hidden_branch)
    hidden_staff = Repo.preload(hidden_staff, [:role, :branches])

    {:ok, _} =
      Features.configure("marketing_policies", {:branch, hidden_branch.id}, true, actor: "test")

    {:ok, hidden_segment} =
      Segments.create(
        hidden_staff,
        %{name: "Hidden audience", kind: :manual, scope: :branches},
        [hidden_branch.id]
      )

    hidden_promotion =
      insert_promotion(hidden_branch.id, kind: :personal_code, rules: "then discount 10%")

    {:ok, hidden_policy} =
      Marketing.create(
        hidden_staff,
        policy_attrs(
          "Hidden comparison",
          hidden_segment.id,
          hidden_branch.id,
          hidden_promotion.id
        ),
        [hidden_branch.id]
      )

    {:ok, view, _} = live(ctx.conn, ~p"/staff/marketing/#{current.id}")
    view |> element("#marketing-report-toggle") |> render_click()
    assert has_element?(view, "#marketing-more-comparison-policies")
    assert has_element?(view, "#marketing-compare button[phx-value-id='#{first_page_choice.id}']")
    refute has_element?(view, "#marketing-compare button[phx-value-id='#{later_choice.id}']")
    refute has_element?(view, "#marketing-compare button[phx-value-id='#{hidden_policy.id}']")

    view
    |> element("#marketing-compare button[phx-value-id='#{first_page_choice.id}']")
    |> render_click()

    view |> element("#marketing-more-comparison-policies") |> render_click()
    assert has_element?(view, "#marketing-compare button[phx-value-id='#{later_choice.id}']")
    refute has_element?(view, "#marketing-more-comparison-policies")

    view
    |> element("#marketing-compare button[phx-value-id='#{later_choice.id}']")
    |> render_click()

    assert has_element?(
             view,
             "#marketing-compare button[phx-value-id='#{first_page_choice.id}'][class*='border-primary']"
           )

    assert has_element?(
             view,
             "#marketing-compare button[phx-value-id='#{later_choice.id}'][class*='border-primary']"
           )

    refute has_element?(view, "#marketing-compare button[phx-value-id='#{hidden_policy.id}']")
  end

  test "ready report displays revenue and discounts in rubles", ctx do
    enable_marketing(ctx)
    staff = Repo.preload(ctx.staff, [:role, :branches])

    {:ok, segment} =
      Segments.create(staff, %{name: "Revenue audience", kind: :manual, scope: :branches}, [
        ctx.branch.id
      ])

    promotion = insert_promotion(ctx.branch.id, kind: :personal_code, rules: "then discount 10%")

    {:ok, policy} =
      Marketing.create(
        staff,
        policy_attrs("Revenue report", segment.id, ctx.branch.id, promotion.id),
        [ctx.branch.id]
      )

    filters = %{
      "from" => Date.add(Date.utc_today(), -29) |> Date.to_iso8601(),
      "to" => Date.utc_today() |> Date.to_iso8601(),
      "branch_id" => ""
    }

    {:ok, %{status: :pending}} = Marketing.report(staff, policy.id, filters)

    report_data = %{
      "linked_net_revenue" => 1_134_000,
      "recorded_promo_discount" => 12_345,
      "series" => [
        %{
          "day" => "2026-11-10",
          "issued" => 1,
          "linked_orders" => 1,
          "linked_net_revenue" => 1_134_000
        }
      ]
    }

    Repo.query!(
      "UPDATE marketing_report_requests SET status='ready', as_of=now(), data=$2::jsonb WHERE policy_id=$1",
      [Ecto.UUID.dump!(policy.id), Jason.encode!(report_data)]
    )

    {:ok, view, _} = live(ctx.conn, ~p"/staff/marketing/#{policy.id}")
    refute has_element?(view, "#marketing-report-form")
    assert has_element?(view, "#marketing-report-toggle[aria-expanded='false']")
    view |> element("#marketing-report-toggle") |> render_click()
    assert has_element?(view, "#marketing-report-toggle[aria-expanded='true']")
    view |> form("#marketing-report-form", report: %{}) |> render_submit()
    assert has_element?(view, "#marketing-report-result", "11 340 ₽")
    assert has_element?(view, "#marketing-report-result", "123,45 ₽")
    assert has_element?(view, "#marketing-report-daily", "11 340 ₽")

    view
    |> form("#marketing-report-form", report: %{"from" => "2026-10-01", "to" => "2026-10-31"})
    |> render_change()

    assert has_element?(view, "#marketing-report-result", "11 340 ₽")

    view |> element("#marketing-report-toggle") |> render_click()
    refute has_element?(view, "#marketing-report-form")
    view |> element("#marketing-report-toggle") |> render_click()

    assert has_element?(
             view,
             "#marketing-report-form input[name='report[from]'][value='2026-10-01']"
           )

    assert has_element?(
             view,
             "#marketing-report-form input[name='report[to]'][value='2026-10-31']"
           )

    assert has_element?(view, "#marketing-report-result", "11 340 ₽")
  end

  test "report action is unavailable without report permission", ctx do
    enable_marketing(ctx)
    staff = Repo.preload(ctx.staff, [:role, :branches])

    {:ok, segment} =
      Segments.create(staff, %{name: "Read-only audience", kind: :manual, scope: :branches}, [
        ctx.branch.id
      ])

    promotion = insert_promotion(ctx.branch.id, kind: :personal_code, rules: "then discount 10%")

    {:ok, policy} =
      Marketing.create(
        staff,
        policy_attrs("Read-only report", segment.id, ctx.branch.id, promotion.id),
        [ctx.branch.id]
      )

    reportless_staff =
      insert(:staff, role: insert(:role, permissions: ~w(marketing.read)))

    insert(:staff_branch, staff: reportless_staff, branch: ctx.branch)
    conn = init_test_session(ctx.conn, %{"staff_id" => reportless_staff.id})
    {:ok, view, _} = live(conn, ~p"/staff/marketing/#{policy.id}")

    refute has_element?(view, "#marketing-report-toggle")
    refute has_element?(view, "#marketing-report-form")
    render_hook(view, "toggle_report", %{})
    refute has_element?(view, "#marketing-report-form")
  end

  test "paused policy can be edited without changing historical scope or restarting", ctx do
    {_staff, policy} = policy_fixture(ctx, "Paused policy")
    started_at = DateTime.utc_now(:second)

    Repo.update!(
      Ecto.Changeset.change(policy,
        status: :paused,
        activated_at: started_at,
        issued_count: 3
      )
    )

    {:ok, detail, _} = live(ctx.conn, ~p"/staff/marketing/#{policy.id}")
    assert has_element?(detail, "a[href='/staff/marketing/#{policy.id}/edit']")
    {:ok, edit, _} = live(ctx.conn, ~p"/staff/marketing/#{policy.id}/edit")
    assert has_element?(edit, "#marketing-paused-edit-note")
    assert has_element?(edit, "#marketing-immutable-note")
    refute has_element?(edit, "#marketing-policy-audience select[name='policy[scope]']")
    refute has_element?(edit, "#marketing-policy-limits select[name='policy[initial_mode]']")
    refute has_element?(edit, "#marketing-policy-audience button[phx-click='toggle_branch']")

    edit
    |> form("#marketing-policy-audience", policy: %{name: "Changed future policy"})
    |> render_submit()

    edit |> form("#marketing-policy-reward", policy: %{}) |> render_submit()

    edit
    |> form("#marketing-policy-message", policy: %{message_body: "Future reward"})
    |> render_submit()

    edit |> form("#marketing-policy-limits", policy: %{inactivity_days: "45"}) |> render_submit()
    edit |> element("#marketing-save") |> render_click()
    assert_redirect(edit)

    updated = Repo.get!(Delivest.Marketing.Policy, policy.id)
    assert updated.status == :paused
    assert updated.activated_at == started_at
    assert updated.issued_count == 3
    assert updated.name == "Changed future policy"
    assert updated.message_body == "Future reward"
    assert updated.inactivity_days == 45
    assert updated.scope == policy.scope and updated.initial_mode == policy.initial_mode
  end

  test "active policy explains pause before editing and redirects direct edit", ctx do
    {_staff, policy} = policy_fixture(ctx, "Active policy")

    Repo.update!(
      Ecto.Changeset.change(policy, status: :active, activated_at: DateTime.utc_now(:second))
    )

    {:ok, detail, _} = live(ctx.conn, ~p"/staff/marketing/#{policy.id}")
    assert has_element?(detail, "#marketing-active-edit-hint")
    assert has_element?(detail, "#marketing-pause")
    refute has_element?(detail, "a[href='/staff/marketing/#{policy.id}/edit']")

    show_path = ~p"/staff/marketing/#{policy.id}"

    assert {:error, {:live_redirect, %{to: ^show_path}}} =
             live(ctx.conn, ~p"/staff/marketing/#{policy.id}/edit")
  end

  test "draft delete confirmation can be cancelled before a hard delete", ctx do
    {_staff, policy} = policy_fixture(ctx, "Draft deletion")
    grant_delete(ctx.staff)
    {:ok, view, _} = live(ctx.conn, ~p"/staff/marketing/#{policy.id}")

    view |> element("#marketing-delete") |> render_click()

    assert has_element?(
             view,
             "#marketing-delete-dialog",
             "This draft will be deleted permanently"
           )

    assert has_element?(view, "#marketing-delete-title", "Draft deletion")

    assert has_element?(
             view,
             "#marketing-delete-dialog[phx-window-keydown='cancel_delete'][phx-key='escape']"
           )

    assert has_element?(view, "#marketing-delete-focus[phx-hook='Phoenix.FocusWrap']")

    view |> element("#marketing-cancel-delete") |> render_click()
    refute has_element?(view, "#marketing-delete-dialog")
    assert Repo.get(Delivest.Marketing.Policy, policy.id)

    view |> element("#marketing-delete") |> render_click()
    view |> element("#marketing-confirm-delete") |> render_click()
    assert_redirect(view, ~p"/staff/marketing/policies")
    refute Repo.get(Delivest.Marketing.Policy, policy.id)
  end

  test "started delete hides management but keeps deleted history and report", ctx do
    {_staff, policy} = policy_fixture(ctx, "Started deletion")
    grant_delete(ctx.staff)

    Repo.update!(
      Ecto.Changeset.change(policy, status: :paused, activated_at: DateTime.utc_now(:second))
    )

    {:ok, view, _} = live(ctx.conn, ~p"/staff/marketing/#{policy.id}")
    view |> element("#marketing-delete") |> render_click()

    assert has_element?(
             view,
             "#marketing-delete-dialog",
             "History, reports, and issued rewards will remain"
           )

    view |> element("#marketing-confirm-delete") |> render_click()
    assert_redirect(view, ~p"/staff/marketing/policies")

    {:ok, working, _} = live(ctx.conn, ~p"/staff/marketing/policies")
    refute has_element?(working, "a", "Started deletion")
    working |> element("#marketing-list-filter a", "Deleted policies") |> render_click()
    assert has_element?(working, "a", "Started deletion")
    {:ok, history, _} = live(ctx.conn, ~p"/staff/marketing/#{policy.id}")
    assert has_element?(history, "#marketing-deleted-note")
    assert has_element?(history, "#marketing-report-toggle")
    refute has_element?(history, "#marketing-delete")
    refute has_element?(history, "#marketing-activate")
    refute has_element?(history, "a[href='/staff/marketing/#{policy.id}/edit']")
  end

  test "forged delete without permission or pending confirmation does nothing", ctx do
    {_staff, policy} = policy_fixture(ctx, "Protected")
    {:ok, view, _} = live(ctx.conn, ~p"/staff/marketing/#{policy.id}")
    refute has_element?(view, "#marketing-delete")
    render_hook(view, "open_delete", %{})
    render_hook(view, "confirm_delete", %{})
    refute has_element?(view, "#marketing-delete-dialog")
    assert Repo.get(Delivest.Marketing.Policy, policy.id)
  end

  test "stale confirmation never deletes a changed policy", ctx do
    {_staff, policy} = policy_fixture(ctx, "Stale deletion")
    grant_delete(ctx.staff)
    {:ok, view, _} = live(ctx.conn, ~p"/staff/marketing/#{policy.id}")
    view |> element("#marketing-delete") |> render_click()
    Repo.update!(Ecto.Changeset.change(policy, revision: policy.revision + 1))
    view |> element("#marketing-confirm-delete") |> render_click()
    refute has_element?(view, "#marketing-delete-dialog")
    assert has_element?(view, "#flash-error", "Policy changed")
    assert Repo.get(Delivest.Marketing.Policy, policy.id)
  end

  test "lifecycle controls and confirmation read naturally in Russian", ctx do
    {_staff, policy} = policy_fixture(ctx, "Russian policy")
    grant_delete(ctx.staff)
    conn = init_test_session(ctx.conn, %{"locale" => "ru"})
    {:ok, index, _} = live(conn, ~p"/staff/marketing/policies")
    assert has_element?(index, "#marketing-list-filter", "Рабочий список")
    assert has_element?(index, "#marketing-list-filter", "Удалённые")

    {:ok, detail, _} = live(conn, ~p"/staff/marketing/#{policy.id}")
    detail |> element("#marketing-delete") |> render_click()
    assert has_element?(detail, "#marketing-delete-title", "Russian policy")
    assert has_element?(detail, "#marketing-delete-dialog", "Черновик будет удалён полностью")
    detail |> element("#marketing-cancel-delete") |> render_click()
    assert Repo.get(Delivest.Marketing.Policy, policy.id)
  end

  defp policy_fixture(ctx, name) do
    enable_marketing(ctx)
    staff = Repo.preload(ctx.staff, [:role, :branches])

    {:ok, segment} =
      Segments.create(staff, %{name: "#{name} audience", kind: :manual, scope: :branches}, [
        ctx.branch.id
      ])

    promotion = insert_promotion(ctx.branch.id, kind: :personal_code, rules: "then discount 10%")

    {:ok, policy} =
      Marketing.create(staff, policy_attrs(name, segment.id, ctx.branch.id, promotion.id), [
        ctx.branch.id
      ])

    {staff, policy}
  end

  defp grant_delete(staff) do
    staff = Repo.preload(staff, :role)

    Repo.update!(
      Ecto.Changeset.change(staff.role,
        permissions: staff.role.permissions ++ ["marketing.delete"]
      )
    )
  end

  defp policy_attrs(name, segment_id, branch_id, promotion_id) do
    %{
      "name" => name,
      "scope" => "branches",
      "segment_id" => segment_id,
      "reward_branch_id" => branch_id,
      "promotion_id" => promotion_id,
      "inactivity_days" => 30,
      "reward_ttl_days" => 14,
      "attribution_days" => 7,
      "initial_mode" => "future_only",
      "channels" => ["in_app"],
      "message_title" => "Come back",
      "message_body" => "Your reward is ready"
    }
  end

  defp enable_marketing(ctx) do
    {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "test")

    {:ok, _} =
      Features.configure("marketing_policies", {:branch, ctx.branch.id}, true, actor: "test")
  end
end
