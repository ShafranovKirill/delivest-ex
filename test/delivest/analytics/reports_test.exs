defmodule Delivest.Analytics.ReportsTest do
  use Delivest.DataCase, async: false
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.{Analytics.Reports, Background, Features, LocalTime, Repo}
  alias Delivest.Analytics.Reports.Query
  alias Delivest.Oms.Order

  setup do
    branch = insert(:branch)
    analyst = insert(:staff, role: insert(:role, permissions: ["statistics.read"]))
    insert(:staff_branch, staff: analyst, branch: branch)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))

    %{
      branch: branch,
      analyst: Repo.preload(analyst, [:role, :branches]),
      admin: Repo.preload(admin, [:role, :branches])
    }
  end

  defp today(branch), do: LocalTime.today(LocalTime.timezone(branch.id))

  defp enable(feature, branch) do
    assert {:ok, _} = Features.configure(feature, :franchise, true, actor: "host")
    assert {:ok, _} = Features.configure(feature, {:branch, branch.id}, true, actor: "host")
  end

  defp run_report(kind, branch) do
    assert {:ok, :queued} = Background.run_now(kind, {:branch, branch.id}, new_work: true)
    assert {:ok, count} = Background.dispatch_due()
    assert count >= 1
    assert %{success: success} = Oban.drain_queue(queue: :background, with_safety: false)
    assert success >= 1
  end

  test "disabled extended analytics writes no identity or report and refuses reads", ctx do
    order = order_fixture(ctx.branch.id)

    assert {:error, :forbidden} =
             Reports.read(
               ctx.analyst,
               {:branch, ctx.branch.id},
               {today(ctx.branch), today(ctx.branch)},
               "channels"
             )

    assert Repo.query!(
             "SELECT count(*) FROM analytics_order_identities WHERE order_id=$1::text::uuid",
             [order.id]
           ).rows == [[0]]

    assert Repo.query!(
             "SELECT count(*) FROM analytics_report_states WHERE branch_id=$1::text::uuid",
             [ctx.branch.id]
           ).rows == [[0]]

    assert {:error, :disabled} =
             Background.run_now("analytics.extended", {:branch, ctx.branch.id})
  end

  test "published completed revenue is corrected without double counting", ctx do
    enable("analytics_extended", ctx.branch)
    order = order_fixture(ctx.branch.id, price: 12_345)

    assert Repo.query!(
             "SELECT owner_kind FROM analytics_order_identities WHERE order_id=$1::text::uuid",
             [order.id]
           ).rows == [["unknown"]]

    Repo.update!(Ecto.Changeset.change(order, status: :completed))
    run_report("analytics.extended", ctx.branch)
    period = {today(ctx.branch), today(ctx.branch)}

    assert {:ok, %{rows: [%{counts: %{"completed" => 1, "revenue" => 12_345}}]}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, period, "channels")

    assert {:ok, %{verified_buyers: 0}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, period, "customers")

    Repo.update!(Ecto.Changeset.change(Repo.reload!(order), status: :created))
    run_report("analytics.extended", ctx.branch)

    assert {:ok, %{rows: [%{counts: %{"completed" => 0, "revenue" => 0}}]}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, period, "channels")
  end

  test "branch and network reads enforce permission and feature scope", ctx do
    other = insert(:branch)
    enable("analytics_franchise", ctx.branch)

    assert {:ok, _} =
             Features.configure("analytics_franchise", {:branch, other.id}, true, actor: "host")

    order = order_fixture(ctx.branch.id, price: 1_000)
    Repo.update!(Ecto.Changeset.change(order, status: :completed))
    run_report("analytics.extended", ctx.branch)

    period = {today(ctx.branch), today(ctx.branch)}
    assert {:error, :forbidden} = Reports.read(ctx.analyst, :franchise, period, "franchise")

    assert {:error, :forbidden} =
             Reports.read(ctx.analyst, {:branch, other.id}, period, "channels")

    assert {:ok, %{totals: %{"revenue" => 1_000}}} =
             Reports.read(ctx.admin, :franchise, period, "franchise")
  end

  test "manual rebuild is host admin only and never runs on read", ctx do
    enable("analytics_extended", ctx.branch)
    period = {today(ctx.branch), today(ctx.branch)}

    assert {:error, :forbidden} =
             Reports.request_rebuild(ctx.analyst, "analytics_extended", ctx.branch.id, period)

    assert {:ok, %{state: :not_collected}} =
             Reports.read(ctx.analyst, {:branch, ctx.branch.id}, period, "channels")

    assert {:ok, :queued} =
             Reports.request_rebuild(ctx.admin, "analytics_extended", ctx.branch.id, period)
  end

  test "published dimensions are aggregated and paged in SQL", ctx do
    day = today(ctx.branch)
    snapshot = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.query!(
      "INSERT INTO analytics_report_snapshots(id,feature,branch_id,day,revision,franchise_generation,branch_generation,source_asof,inserted_at) VALUES ($1::text::uuid,'analytics_extended',$2::text::uuid,$3,0,1,1,$4,$4)",
      [snapshot, ctx.branch.id, day, now]
    )

    Repo.query!(
      "INSERT INTO analytics_report_states(feature,branch_id,day,revision,snapshot_id,published_at,source_asof,inserted_at,updated_at) VALUES ('analytics_extended',$1::text::uuid,$2,0,$3::text::uuid,$4,$4,$4,$4)",
      [ctx.branch.id, day, snapshot, now]
    )

    keys = for n <- 1..60, do: "source-#{String.pad_leading(Integer.to_string(n), 2, "0")}"

    Repo.query!(
      "INSERT INTO analytics_report_rows(snapshot_id,family,dimension,key,counts) SELECT $1::text::uuid,'extended','channel',k,'{\"created\":1,\"completed\":1,\"revenue\":100}'::jsonb FROM unnest($2::text[]) k",
      [snapshot, keys]
    )

    first = Query.read("analytics_extended", [ctx.branch.id], day, day, "channels", %{}, 1)
    second = Query.read("analytics_extended", [ctx.branch.id], day, day, "channels", %{}, 2)

    assert first.total_rows == 60
    assert length(first.rows) == 50
    assert length(second.rows) == 10
    assert first.totals["revenue"] == 6_000
    assert second.rows |> hd() |> Map.fetch!(:key) == "source-51"
  end
end
