defmodule Delivest.Net.StopPeriod do
  alias Delivest.LocalTime

  def periods, do: [:today, :until_resumed]

  def until(period, now, branch_id \\ nil)

  def until(:until_resumed, _now, _branch_id), do: nil

  def until(:today, %DateTime{} = now, branch_id) do
    zone = LocalTime.timezone(branch_id)

    now
    |> LocalTime.business_date(zone)
    |> Date.add(1)
    |> NaiveDateTime.new!(LocalTime.day_starts_at())
    |> LocalTime.naive_to_utc(zone)
    |> DateTime.truncate(:second)
  end

  def active?(%{until: nil}, _now), do: true
  def active?(%{until: until}, now), do: DateTime.after?(until, now)
end
