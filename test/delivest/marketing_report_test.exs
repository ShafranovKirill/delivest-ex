defmodule Delivest.Marketing.ReportTest do
  use Delivest.DataCase, async: false
  import Delivest.Factory

  alias Delivest.{Features, Marketing, Repo}
  alias Delivest.Background.Schedule
  alias Delivest.Marketing.{Policy, Report}
  alias Delivest.Oms.{Cart, Order, OrderTransition}
  alias Delivest.Segments.Segment

  setup do
    branch = insert(:branch)
    client = insert(:client)
    assert {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "test")

    assert {:ok, _} =
             Features.configure("marketing_policies", {:branch, branch.id}, true, actor: "test")

    segment = Repo.insert!(%Segment{name: "Audience", kind: :manual, scope: :branches})

    policy =
      Repo.insert!(%Policy{
        name: "Offer",
        segment_id: segment.id,
        scope: :branches,
        reward_branch_id: branch.id,
        bonus_amount: 1,
        inactivity_days: 1,
        reward_ttl_days: 1,
        attribution_days: 7,
        status: :active,
        message_title: "Offer",
        message_body: "Text"
      })

    Repo.insert_all("marketing_policy_branches", [
      %{policy_id: Ecto.UUID.dump!(policy.id), branch_id: Ecto.UUID.dump!(branch.id)}
    ])

    schedule =
      Repo.get_by(Schedule, kind: "marketing.report", scope_key: "franchise") ||
        Repo.insert!(%Schedule{
          kind: "marketing.report",
          scope_key: "franchise",
          next_at: DateTime.utc_now()
        })

    Repo.update!(Ecto.Changeset.change(schedule, running: true, current_job_id: 987_654))
    assert {:ok, generation} = Features.snapshot("marketing_policies", :franchise)

    context = %{
      feature: "marketing_policies",
      scope: :franchise,
      generation: generation,
      schedule_id: schedule.id,
      job_id: 987_654
    }

    %{branch: branch, client: client, policy: policy, context: context}
  end

  test "comparison polling authorizes every member policy without creating work", %{
    branch: branch,
    policy: policy
  } do
    other_branch = insert(:branch)

    assert {:ok, _} =
             Features.configure("marketing_policies", {:branch, other_branch.id}, true,
               actor: "test"
             )

    other_policy =
      Repo.insert!(%Policy{
        name: "Other offer",
        segment_id: policy.segment_id,
        scope: :branches,
        reward_branch_id: other_branch.id,
        bonus_amount: 1,
        inactivity_days: 1,
        reward_ttl_days: 1,
        attribution_days: 7,
        status: :active,
        message_title: "Other offer",
        message_body: "Text"
      })

    Repo.insert_all("marketing_policy_branches", [
      %{policy_id: Ecto.UUID.dump!(other_policy.id), branch_id: Ecto.UUID.dump!(other_branch.id)}
    ])

    assert {:ok, %{status: :pending, id: first_id}} = Report.request(policy)
    assert {:ok, %{status: :pending, id: second_id}} = Report.request(other_policy)

    Repo.query!(
      "UPDATE marketing_report_requests SET status='ready',phase='orders',as_of=now(),data='{}'::jsonb WHERE id=ANY($1::uuid[])",
      [[Ecto.UUID.dump!(first_id), Ecto.UUID.dump!(second_id)]]
    )

    assert {:ok, %{id: comparison_id, status: :pending}} =
             Report.compare([policy, other_policy])

    role = insert(:role, permissions: ["marketing.read", "marketing.reports"])
    full = insert(:staff, role: role)
    limited = insert(:staff, role: role)

    for target <- [branch, other_branch], do: insert(:staff_branch, staff: full, branch: target)
    insert(:staff_branch, staff: limited, branch: branch)

    jobs_before = Repo.aggregate(Oban.Job, :count)

    assert {:ok, %{id: ^comparison_id, status: :pending}} =
             Marketing.comparison_status(full, comparison_id)

    assert {:error, :forbidden} = Marketing.comparison_status(limited, comparison_id)
    assert {:ok, nil} = Marketing.comparison_status(full, Ecto.UUID.generate())
    assert Repo.aggregate(Oban.Job, :count) == jobs_before
  end

  test "manual report refreshes a ready cache and preserves its request identity", %{
    policy: policy
  } do
    assert {:ok, %{id: id, status: :pending}} = Report.request(policy)

    Repo.query!(
      "UPDATE marketing_report_requests SET status='ready',phase='orders',as_of=now(),data='{}'::jsonb WHERE id=$1",
      [Ecto.UUID.dump!(id)]
    )

    assert {:ok, %{id: ^id, status: :ready}} = Report.status(policy, id)
    assert {:ok, %{id: ^id, status: :pending}} = Report.recalculate(policy, %{})
    assert {:ok, %{id: ^id, status: :pending}} = Report.status(policy, id)
    assert {:ok, %{id: ^id, status: :pending}} = Report.recalculate(policy, %{})
  end

  test "empty report is pending until bounded background publication", %{
    policy: policy,
    context: context
  } do
    assert {:ok, %{status: :pending}} = Report.request(policy)
    activate_context(context)
    assert Report.perform(:franchise, context) in [:ok, {:snooze, 1}]
    assert {:ok, %{status: :pending}} = Report.request(policy)
    activate_context(context)
    assert Report.perform(:franchise, context) in [:ok, {:snooze, 1}]
    assert {:ok, %{status: :ready, as_of: %DateTime{}, data: data}} = Report.request(policy)
    assert data["issued"] == 0
    assert data["linked_orders"] == 0
    assert data["delivered"] == nil
    assert data["bonus_points_used"] == nil

    assert {:error, :invalid_report_filters} =
             Report.request(
               policy,
               %{from: Date.add(Date.utc_today(), -91), to: Date.utc_today()}
             )
  end

  test "one issue links a later completed order inside its stored window", %{
    policy: policy,
    branch: branch,
    client: client,
    context: context
  } do
    base =
      completed_order(branch, client, DateTime.add(DateTime.utc_now(:second), -3_600, :second))

    issued_at = DateTime.add(DateTime.utc_now(:second), -1_800, :second)

    assert {:ok, source_generation} =
             Features.snapshot("marketing_policies", {:branch, branch.id})

    issue =
      Repo.insert!(%Delivest.Marketing.Issue{
        policy_id: policy.id,
        client_id: client.id,
        cycle_order_id: base.id,
        branch_id: branch.id,
        reward_type: "bonus",
        reward_amount: 7,
        issued_at: issued_at,
        expires_at: DateTime.add(issued_at, 86_400, :second),
        attribution_until: DateTime.add(issued_at, 7 * 86_400, :second),
        policy_revision: 1,
        source_generation_franchise: source_generation.franchise,
        source_generation_branch: source_generation.branch
      })

    linked = completed_order(branch, client, DateTime.add(issued_at, 100, :second))
    assert {:ok, %{status: :pending}} = Report.request(policy)
    activate_context(context)

    for _ <- 1..5,
        do: assert(Report.perform(:franchise, context) in [:ok, {:snooze, 1}])

    assert {:ok, %{status: :ready, data: data}} = Report.request(policy)
    assert data["issued"] == 1
    assert data["bonus_points_issued"] == 7
    assert data["linked_orders"] == 1
    assert data["linked_net_revenue"] == linked.total_amount
    assert data["returned_clients"] == 1
    assert Repo.get!(Delivest.Marketing.Issue, issue.id)
  end

  test "comparison counts an overlapping order only once", %{
    policy: first,
    branch: branch,
    client: client,
    context: context
  } do
    second =
      Repo.insert!(%Policy{
        name: "Second offer",
        segment_id: first.segment_id,
        scope: :branches,
        reward_branch_id: branch.id,
        bonus_amount: 2,
        inactivity_days: 1,
        reward_ttl_days: 1,
        attribution_days: 7,
        status: :active,
        message_title: "Second",
        message_body: "Text"
      })

    Repo.insert_all("marketing_policy_branches", [
      %{policy_id: Ecto.UUID.dump!(second.id), branch_id: Ecto.UUID.dump!(branch.id)}
    ])

    base =
      completed_order(branch, client, DateTime.add(DateTime.utc_now(:second), -3_600, :second))

    issued_at = DateTime.add(DateTime.utc_now(:second), -1_800, :second)

    assert {:ok, source_generation} =
             Features.snapshot("marketing_policies", {:branch, branch.id})

    for policy <- [first, second] do
      Repo.insert!(%Delivest.Marketing.Issue{
        policy_id: policy.id,
        client_id: client.id,
        cycle_order_id: base.id,
        branch_id: branch.id,
        reward_type: "bonus",
        reward_amount: 1,
        issued_at: issued_at,
        expires_at: DateTime.add(issued_at, 86_400, :second),
        attribution_until: DateTime.add(issued_at, 7 * 86_400, :second),
        policy_revision: 1,
        source_generation_franchise: source_generation.franchise,
        source_generation_branch: source_generation.branch
      })

      assert {:ok, %{status: :pending}} = Report.request(policy)
    end

    linked = completed_order(branch, client, DateTime.add(issued_at, 100, :second))
    activate_context(context)

    for _ <- 1..6,
        do: assert(Report.perform(:franchise, context) in [:ok, {:snooze, 1}])

    assert {:ok, %{status: :ready, data: first_data}} = Report.request(first)
    assert {:ok, %{status: :ready, data: second_data}} = Report.request(second)
    assert first_data["linked_orders"] == 1
    assert second_data["linked_orders"] == 1
    assert {:ok, %{status: :pending}} = Report.compare([first, second])
    activate_context(context)
    assert Report.perform(:franchise, context) in [:ok, {:snooze, 1}]
    assert {:ok, %{status: :ready, data: compared}} = Report.compare([first, second])
    assert compared["linked_orders"] == 1
    assert compared["linked_net_revenue"] == linked.total_amount
    assert compared["returned_clients"] == 1
    assert length(compared["return_branches"]) == 1
    assert length(compared["series"]) == 1
  end

  test "branch filter uses issue branch while return order may be at another branch", %{
    policy: policy,
    branch: issue_branch,
    client: client,
    context: context
  } do
    return_branch = insert(:branch)
    policy = Repo.update!(Ecto.Changeset.change(policy, scope: :franchise))
    base = completed_order(issue_branch, client, DateTime.add(DateTime.utc_now(:second), -3_600))
    issued_at = DateTime.add(DateTime.utc_now(:second), -1_800)
    {:ok, generation} = Features.snapshot("marketing_policies", {:branch, issue_branch.id})

    Repo.insert!(%Delivest.Marketing.Issue{
      policy_id: policy.id,
      client_id: client.id,
      cycle_order_id: base.id,
      branch_id: issue_branch.id,
      reward_type: "bonus",
      reward_amount: 1,
      issued_at: issued_at,
      expires_at: DateTime.add(issued_at, 86_400),
      attribution_until: DateTime.add(issued_at, 7 * 86_400),
      policy_revision: 1,
      source_generation_franchise: generation.franchise,
      source_generation_branch: generation.branch
    })

    completed_order(return_branch, client, DateTime.add(issued_at, 100))
    assert {:ok, %{status: :pending}} = Report.request(policy, %{branch_id: issue_branch.id})
    activate_context(context)

    for _ <- 1..5,
        do: assert(Report.perform(:franchise, context) in [:ok, {:snooze, 1}])

    assert {:ok, %{status: :ready, data: data}} =
             Report.request(policy, %{branch_id: issue_branch.id})

    assert data["issued"] == 1
    assert data["linked_orders"] == 1

    issue_branch_id = issue_branch.id
    return_branch_id = return_branch.id

    assert [[^issue_branch_id, 1]] =
             Repo.query!(
               "SELECT branch_id::text, linked_orders FROM marketing_report_daily WHERE request_id=(SELECT id FROM marketing_report_requests WHERE policy_id=$1)",
               [Ecto.UUID.dump!(policy.id)]
             ).rows

    assert [[^return_branch_id, ^issue_branch_id]] =
             Repo.query!(
               "SELECT branch_id::text, issue_branch_id::text FROM marketing_report_links WHERE request_id=(SELECT id FROM marketing_report_requests WHERE policy_id=$1)",
               [Ecto.UUID.dump!(policy.id)]
             ).rows
  end

  test "stale ready cache is cleaned in bounded pages before refresh", %{
    policy: policy,
    branch: branch,
    client: client,
    context: context
  } do
    assert {:ok, %{status: :pending}} = Report.request(policy)
    activate_context(context)
    for _ <- 1..2, do: assert(Report.perform(:franchise, context) in [:ok, {:snooze, 1}])
    assert {:ok, %{id: request_id, status: :ready}} = Report.request(policy)

    rows =
      for day <- 1..55 do
        %{
          request_id: Ecto.UUID.dump!(request_id),
          branch_id: Ecto.UUID.dump!(branch.id),
          day: Date.add(Date.utc_today(), -day)
        }
      end

    Repo.insert_all("marketing_report_daily", rows)

    links =
      for _ <- 1..55 do
        order = completed_order(branch, client, DateTime.utc_now(:second))

        %{
          request_id: Ecto.UUID.dump!(request_id),
          order_id: Ecto.UUID.dump!(order.id),
          client_id: Ecto.UUID.dump!(client.id),
          branch_id: Ecto.UUID.dump!(branch.id),
          issue_branch_id: Ecto.UUID.dump!(branch.id),
          issue_day: Date.utc_today(),
          net_revenue: order.total_amount
        }
      end

    Repo.insert_all("marketing_report_links", links)
    assert {:ok, %{id: comparison_id, status: :pending}} = Report.compare([policy])
    activate_context(context)
    assert {:snooze, 1} = Report.perform(:franchise, context)

    stale = DateTime.add(DateTime.utc_now(:microsecond), -2 * 86_400, :second)

    Repo.query!("UPDATE marketing_report_requests SET as_of=$2 WHERE id=$1", [
      Ecto.UUID.dump!(request_id),
      stale
    ])

    assert {:ok, %{status: :pending, as_of: nil, data: nil}} = Report.request(policy)
    assert {:ok, %{status: :pending}} = Report.compare([policy])

    assert [["stale"]] =
             Repo.query!("SELECT status FROM marketing_report_comparisons WHERE id=$1", [
               Ecto.UUID.dump!(comparison_id)
             ]).rows

    activate_context(context)
    assert {:snooze, 1} = Report.perform(:franchise, context)

    assert [[5]] =
             Repo.query!("SELECT count(*) FROM marketing_report_daily WHERE request_id=$1", [
               Ecto.UUID.dump!(request_id)
             ]).rows

    assert [[5]] =
             Repo.query!("SELECT count(*) FROM marketing_report_links WHERE request_id=$1", [
               Ecto.UUID.dump!(request_id)
             ]).rows

    assert {:ok, %{status: :pending, data: nil}} = Report.request(policy)
    assert {:ok, %{status: :pending}} = Report.compare([policy])

    activate_context(context)
    assert {:snooze, 1} = Report.perform(:franchise, context)
    assert {:ok, %{status: :pending}} = Report.request(policy)
  end

  test "excluded cycle at another branch counts under reward branch filter", %{
    policy: policy,
    branch: reward_branch,
    client: client,
    context: context
  } do
    cycle_branch = insert(:branch)
    policy = Repo.update!(Ecto.Changeset.change(policy, scope: :franchise))
    cycle = completed_order(cycle_branch, client, DateTime.utc_now(:second))

    Repo.insert_all("marketing_exclusions", [
      %{
        policy_id: Ecto.UUID.dump!(policy.id),
        client_id: Ecto.UUID.dump!(client.id),
        cycle_order_id: Ecto.UUID.dump!(cycle.id),
        reason: "excluded",
        inserted_at: DateTime.utc_now(:second)
      }
    ])

    assert {:ok, %{status: :pending}} = Report.request(policy, %{branch_id: reward_branch.id})
    assert {:ok, %{status: :pending}} = Report.request(policy, %{branch_id: cycle_branch.id})
    activate_context(context)

    for _ <- 1..4,
        do: assert(Report.perform(:franchise, context) in [:ok, {:snooze, 1}])

    assert {:ok, %{status: :ready, data: reward_data}} =
             Report.request(policy, %{branch_id: reward_branch.id})

    assert {:ok, %{status: :ready, data: cycle_data}} =
             Report.request(policy, %{branch_id: cycle_branch.id})

    assert reward_data["excluded"] == 1
    assert cycle_data["excluded"] == 0
  end

  defp completed_order(branch, client, completed_at) do
    completed_at = DateTime.from_unix!(DateTime.to_unix(completed_at, :microsecond), :microsecond)
    cart = Repo.insert!(%Cart{branch_id: branch.id, client_id: client.id})

    order =
      Repo.insert!(%Order{
        branch_id: branch.id,
        client_id: client.id,
        cart_id: cart.id,
        number: "R-#{Ecto.UUID.generate()}",
        daily_number: :erlang.unique_integer([:positive]),
        business_date: Date.utc_today(),
        status: :completed,
        total_amount: 200
      })

    Repo.insert!(%OrderTransition{
      order_id: order.id,
      from: :delivering,
      to: :completed,
      source: :system,
      inserted_at: completed_at
    })

    order
  end

  defp activate_context(context) do
    schedule = Repo.get!(Schedule, context.schedule_id)
    Repo.update!(Ecto.Changeset.change(schedule, running: true, current_job_id: context.job_id))
  end
end
