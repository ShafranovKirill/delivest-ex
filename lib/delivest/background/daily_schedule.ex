defmodule Delivest.Background.DailySchedule do
  @moduledoc "Local 03:00 policy for daily background calculations."

  import Ecto.Query, only: [from: 2]

  alias Delivest.Franchise.SettingsStore
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.LocalTime
  alias Delivest.Repo

  @hour ~T[03:00:00]

  def zone("franchise"), do: SettingsStore.current(:timezone) || "Europe/Moscow"

  def zone("branch:" <> id) do
    Repo.one(from i in BranchInfo, where: i.branch_id == ^id, select: i.timezone) ||
      zone("franchise")
  end

  def zone(_), do: zone("franchise")

  def due_at(date, zone) do
    date
    |> NaiveDateTime.new!(@hour)
    |> LocalTime.naive_to_utc(zone)
    |> Map.put(:microsecond, {0, 6})
  end

  def next_future(now, zone) do
    today = now |> DateTime.shift_zone!(zone) |> DateTime.to_date()

    date =
      if DateTime.compare(due_at(today, zone), now) == :gt, do: today, else: Date.add(today, 1)

    {date, due_at(date, zone)}
  end

  def next_after(date, now, zone) do
    {future, _} = next_future(now, zone)
    next = if Date.compare(Date.add(date, 1), future) == :gt, do: Date.add(date, 1), else: future
    {next, due_at(next, zone)}
  end

  def current_local_date(now, zone), do: now |> DateTime.shift_zone!(zone) |> DateTime.to_date()

  def latest_due_date(now, zone) do
    today = current_local_date(now, zone)
    if DateTime.compare(due_at(today, zone), now) == :gt, do: Date.add(today, -1), else: today
  end

  def normalize(row, now, zone) do
    latest = latest_due_date(now, zone)

    latest_at = due_at(latest, zone)

    attempted? =
      Enum.any?([row.last_success_at, row.last_error_at], fn
        nil -> false
        at -> DateTime.compare(at, latest_at) != :lt
      end)

    date =
      cond do
        is_nil(row.daily_date) ->
          if(attempted?, do: Date.add(latest, 1), else: latest)

        Date.compare(row.daily_date, latest) == :lt ->
          if(attempted?, do: Date.add(latest, 1), else: latest)

        Date.compare(row.daily_date, latest) == :eq and attempted? ->
          Date.add(latest, 1)

        true ->
          row.daily_date
      end

    {future, _} = next_future(now, zone)
    date = if Date.compare(date, future) == :gt, do: future, else: date
    {date, due_at(date, zone)}
  end
end
