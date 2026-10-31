defmodule Delivest.LocalTimeTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.LocalTime

  @zone "Asia/Yekaterinburg"

  test "local day bounds are shifted to UTC" do
    assert LocalTime.start_of_day_utc(~D[2026-10-19], @zone) == ~U[2026-10-18 19:00:00Z]
    assert LocalTime.end_of_day_utc(~D[2026-10-19], @zone) == ~U[2026-10-19 18:59:59Z]
  end

  test "today follows the given zone" do
    expected = DateTime.utc_now() |> DateTime.shift_zone!(@zone) |> DateTime.to_date()
    assert LocalTime.today(@zone) == expected
  end

  test "defaults to the franchise zone" do
    assert LocalTime.timezone() == "Europe/Moscow"
    assert LocalTime.timezone(nil) == "Europe/Moscow"
  end

  test "a branch takes its own zone or the franchise one" do
    branch = insert(:branch)
    assert LocalTime.timezone(branch.id) == "Europe/Moscow"

    Delivest.Repo.insert!(%Delivest.Identity.Branch.BranchInfo{
      branch_id: branch.id,
      timezone: @zone
    })

    Cachex.clear(:branch_cache)
    assert LocalTime.timezone(branch.id) == @zone
  end

  test "a naive time is read in the branch zone" do
    assert LocalTime.parse("2026-10-19T18:30", nil) == ~U[2026-10-19 15:30:00Z]
    assert LocalTime.parse("2026-10-19T18:30:00+05:00", nil) == ~U[2026-10-19 13:30:00Z]
  end

  test "the business day starts at five in the morning" do
    assert LocalTime.business_date(~U[2026-10-19 23:59:00Z], @zone) == ~D[2026-10-19]
    assert LocalTime.business_date(~U[2026-10-19 23:59:59Z], @zone) == ~D[2026-10-19]
    assert LocalTime.business_date(~U[2026-10-20 00:00:00Z], @zone) == ~D[2026-10-20]
    assert LocalTime.business_date(~U[2026-10-19 12:00:00Z], @zone) == ~D[2026-10-19]
  end
end
