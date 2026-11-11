defmodule Delivest.Background.DailyScheduleTest do
  use ExUnit.Case, async: true

  alias Delivest.Background.DailySchedule

  test "local 03:00 resolves spring gap and autumn fold deterministically" do
    assert DailySchedule.due_at(~D[2026-03-29], "Europe/Helsinki") ==
             ~U[2026-03-29 01:00:00.000000Z]

    assert DailySchedule.due_at(~D[2026-10-25], "Europe/Helsinki") ==
             ~U[2026-10-25 00:00:00.000000Z]
  end

  test "same UTC instant produces different branch-local due times" do
    now = ~U[2026-06-01 01:00:00.000000Z]

    assert DailySchedule.next_future(now, "Europe/Moscow") ==
             {~D[2026-06-02], ~U[2026-06-02 00:00:00.000000Z]}

    assert DailySchedule.next_future(now, "America/New_York") ==
             {~D[2026-06-01], ~U[2026-06-01 07:00:00.000000Z]}
  end

  test "legacy rolling row catches up once, and a completed local date advances" do
    now = ~U[2026-06-05 12:00:00.000000Z]
    row = %{daily_date: nil, last_success_at: nil, last_error_at: nil}

    assert DailySchedule.normalize(row, now, "Europe/Moscow") ==
             {~D[2026-06-05], ~U[2026-06-05 00:00:00.000000Z]}

    completed = %{row | last_success_at: ~U[2026-06-05 01:00:00.000000Z]}

    assert DailySchedule.normalize(completed, now, "Europe/Moscow") ==
             {~D[2026-06-06], ~U[2026-06-06 00:00:00.000000Z]}
  end

  test "overdue rows clamp to latest local date and timezone changes recompute UTC" do
    now = ~U[2026-06-05 12:00:00.000000Z]
    row = %{daily_date: ~D[2026-06-01], last_success_at: nil, last_error_at: nil}

    assert DailySchedule.normalize(row, now, "Europe/Moscow") ==
             {~D[2026-06-05], ~U[2026-06-05 00:00:00.000000Z]}

    future = %{row | daily_date: ~D[2026-06-06]}

    assert DailySchedule.normalize(future, now, "America/New_York") ==
             {~D[2026-06-06], ~U[2026-06-06 07:00:00.000000Z]}
  end

  test "dateline timezone change caps an old future date at the next local 03:00" do
    now = ~U[2026-06-01 11:00:00.000000Z]

    assert DailySchedule.next_future(now, "Pacific/Kiritimati") ==
             {~D[2026-06-02], ~U[2026-06-01 13:00:00.000000Z]}

    row = %{daily_date: ~D[2026-06-02], last_success_at: nil, last_error_at: nil}

    assert DailySchedule.normalize(row, now, "Etc/GMT+12") ==
             {~D[2026-06-01], ~U[2026-06-01 15:00:00.000000Z]}
  end
end
