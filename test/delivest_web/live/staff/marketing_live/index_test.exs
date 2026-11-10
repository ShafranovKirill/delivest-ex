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
             live(conn, ~p"/staff/marketing")
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

    {:ok, index, _} = live(conn, ~p"/staff/marketing")
    assert has_element?(index, "h1", "Маркетинговые политики")
    assert has_element?(index, "a", "Новая политика")

    {:ok, view, _} = live(conn, ~p"/staff/marketing/new")
    assert has_element?(view, "#marketing-policy-wizard", "Шаг 1 из 5")
    assert has_element?(view, "#marketing-policy-audience", "Аудитория")
    refute has_element?(view, "#marketing-more-segments")
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
