defmodule Delivest.Integrations.YandexEda.ScheduleTest do
  use ExUnit.Case, async: true

  alias Delivest.Integrations.YandexEda.Schedule

  defp day(open, close, enabled \\ true),
    do: %{"enabled" => enabled, "open" => open, "close" => close}

  test "a regular day is one interval" do
    schedule = Schedule.build(%{"monday" => day("09:00", "22:00")})

    assert schedule["mon"] == [%{start: "09:00", end: "22:00"}]
    assert schedule["tue"] == []
  end

  test "closing at midnight ends the day at 24:00" do
    schedule = Schedule.build(%{"friday" => day("10:00", "00:00")})

    assert schedule["fri"] == [%{start: "10:00", end: "24:00"}]
    assert schedule["sat"] == []
  end

  test "hours past midnight move to the next day" do
    schedule =
      Schedule.build(%{"saturday" => day("12:00", "02:00"), "sunday" => day("12:00", "03:00")})

    assert schedule["sat"] == [%{start: "12:00", end: "24:00"}]
    assert schedule["sun"] == [%{start: "00:00", end: "02:00"}, %{start: "12:00", end: "24:00"}]
    assert schedule["mon"] == [%{start: "00:00", end: "03:00"}]
  end

  test "disabled and empty days are closed" do
    schedule = Schedule.build(%{"monday" => day("09:00", "22:00", false), "tuesday" => %{}})

    assert schedule["mon"] == []
    assert schedule["tue"] == []
    assert Schedule.build(nil) |> Map.values() |> Enum.all?(&(&1 == []))
  end
end
