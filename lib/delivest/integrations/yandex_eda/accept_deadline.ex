defmodule Delivest.Integrations.YandexEda.AcceptDeadline do
  alias Delivest.Integrations.YandexEda.Schedule
  alias Delivest.LocalTime

  @keys ~w(mon tue wed thu fri sat sun)
  @days_ahead 7

  def at(working_hours, minutes, zone, now \\ DateTime.utc_now()) do
    now
    |> opening(Schedule.build(working_hours), zone)
    |> DateTime.add(minutes, :minute)
    |> DateTime.truncate(:second)
  end

  defp opening(now, schedule, zone) do
    local = LocalTime.utc_to_naive(now, zone)

    local
    |> NaiveDateTime.to_date()
    |> intervals(schedule)
    |> Enum.find_value(now, fn {start, finish} ->
      cond do
        NaiveDateTime.compare(local, finish) != :lt -> nil
        NaiveDateTime.compare(local, start) != :lt -> now
        true -> LocalTime.naive_to_utc(start, zone)
      end
    end)
  end

  defp intervals(today, schedule) do
    for offset <- 0..@days_ahead,
        date = Date.add(today, offset),
        %{start: start, end: finish} <- Enum.sort_by(schedule[key(date)], & &1.start),
        do: {at_time(date, start), at_time(date, finish)}
  end

  defp key(date), do: Enum.at(@keys, Date.day_of_week(date) - 1)

  defp at_time(date, "24:00"), do: date |> Date.add(1) |> NaiveDateTime.new!(~T[00:00:00])
  defp at_time(date, time), do: NaiveDateTime.new!(date, Time.from_iso8601!(time <> ":00"))
end
