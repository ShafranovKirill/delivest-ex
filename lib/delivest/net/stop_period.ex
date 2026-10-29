defmodule Delivest.Net.StopPeriod do
  alias Delivest.LocalTime

  def periods, do: [:today, :until_resumed]

  def until(:until_resumed, _now), do: nil

  def until(:today, %DateTime{} = now) do
    now
    |> LocalTime.business_date()
    |> Date.add(1)
    |> NaiveDateTime.new!(LocalTime.day_starts_at())
    |> LocalTime.naive_to_utc()
    |> DateTime.truncate(:second)
  end

  def active?(%{until: nil}, _now), do: true
  def active?(%{until: until}, now), do: DateTime.after?(until, now)
end
