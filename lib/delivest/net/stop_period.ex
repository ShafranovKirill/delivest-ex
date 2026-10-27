defmodule Delivest.Net.StopPeriod do
  alias Delivest.LocalTime

  @day_starts_at ~T[05:00:00]

  def periods, do: [:today, :until_resumed]

  def until(:until_resumed, _now), do: nil

  def until(:today, %DateTime{} = now) do
    local = DateTime.shift_zone!(now, LocalTime.timezone())

    local
    |> DateTime.to_date()
    |> Date.add(if Time.before?(DateTime.to_time(local), @day_starts_at), do: 0, else: 1)
    |> NaiveDateTime.new!(@day_starts_at)
    |> LocalTime.naive_to_utc()
    |> DateTime.truncate(:second)
  end

  def active?(%{until: nil}, _now), do: true
  def active?(%{until: until}, now), do: DateTime.after?(until, now)
end
