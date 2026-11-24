# Deterministic historical orders for the chart browser scenarios. Re-running
# the seed keeps the same fixtures and never modifies existing customer orders.
alias Delivest.{LocalTime, Repo}
alias Delivest.Analytics.{OrderHeatmap, SalesCache}
alias Delivest.Identity.Branch
alias Delivest.Oms.Order

branch = Repo.get_by!(Branch, slug: "e2e")
zone = LocalTime.timezone(branch.id)
{from, to} = OrderHeatmap.default_period({:branch, branch.id})

for day <- Date.range(from, to),
    Date.day_of_week(day) == 5,
    {fulfillment, offset} <- [{:pickup, 0}, {:delivery, 1}] do
  number = "chart-fixture-#{day}-#{fulfillment}"

  unless Repo.get_by(Order, branch_id: branch.id, number: number) do
    at = day |> LocalTime.start_of_day_utc(zone) |> DateTime.add((18 + offset) * 3600)

    %Order{}
    |> Ecto.Changeset.change(%{
      number: number,
      branch_id: branch.id,
      cart_id: Ecto.UUID.generate(),
      business_date: day,
      daily_number: 900_000 + offset,
      status: :completed,
      source: "app",
      fulfillment_type: fulfillment,
      payment_method: :cash,
      total_amount: 125_000,
      subtotal_amount: 125_000,
      inserted_at: at,
      updated_at: at
    })
    |> Repo.insert!()
  end

  order = Repo.get_by!(Order, branch_id: branch.id, number: number)
  :ok = Delivest.Analytics.OrderIdentity.capture(order, [], order.inserted_at)

  Repo.query!(
    "UPDATE analytics_report_states SET revision=revision+1 WHERE branch_id=$1::uuid AND day=$2 AND feature='analytics_extended'",
    [Ecto.UUID.dump!(branch.id), day]
  )
end

for day <- Date.range(from, to), Date.day_of_week(day) == 5 do
  Repo.query!(
    "INSERT INTO sales_daily_rollups(branch_id,day,dirty) VALUES ($1::uuid,$2,true) " <>
      "ON CONFLICT(branch_id,day) DO UPDATE SET dirty=true",
    [Ecto.UUID.dump!(branch.id), day]
  )

  {:ok, _} = SalesCache.rebuild_day(branch.id, day)
end

# Publish the same daily report buckets the ranking reads in normal use.
today = LocalTime.today(zone)

Delivest.Analytics.Reports.Refresh.on_read(
  "analytics_extended",
  [branch.id],
  {Date.beginning_of_month(today), today},
  bucket_limit: 100,
  budget_ms: 60_000
)
