defmodule Delivest.Integrations.YandexEda.AcceptDeadlineTest do
  use ExUnit.Case, async: true

  alias Delivest.Integrations.YandexEda.AcceptDeadline
  alias Delivest.LocalTime

  @hours %{
    "monday" => %{"enabled" => true, "open" => "10:00", "close" => "22:00"},
    "tuesday" => %{"enabled" => true, "open" => "10:00", "close" => "02:00"},
    "wednesday" => %{"enabled" => true, "open" => "11:00", "close" => "22:00"}
  }

  defp local(naive), do: LocalTime.naive_to_utc(naive)

  defp deadline(naive, hours \\ @hours),
    do: hours |> AcceptDeadline.at(10, local(naive)) |> LocalTime.utc_to_naive()

  test "during working hours the deadline is ten minutes from now" do
    assert deadline(~N[2026-10-26 15:00:00]) == ~N[2026-10-26 15:10:00]
  end

  test "before opening the deadline counts from the opening" do
    assert deadline(~N[2026-10-26 07:30:00]) == ~N[2026-10-26 10:10:00]
  end

  test "at night the deadline moves to the next opening" do
    assert deadline(~N[2026-10-26 23:40:00]) == ~N[2026-10-27 10:10:00]
  end

  test "hours past midnight still count as open" do
    assert deadline(~N[2026-10-28 01:00:00]) == ~N[2026-10-28 01:10:00]
    assert deadline(~N[2026-10-28 03:00:00]) == ~N[2026-10-28 11:10:00]
  end

  test "closed days are skipped" do
    assert deadline(~N[2026-10-28 23:00:00]) == ~N[2026-11-02 10:10:00]
  end

  test "without working hours the branch is always open" do
    assert deadline(~N[2026-10-26 03:00:00], %{}) == ~N[2026-10-26 03:10:00]
    assert deadline(~N[2026-10-26 03:00:00], nil) == ~N[2026-10-26 03:10:00]
  end
end
