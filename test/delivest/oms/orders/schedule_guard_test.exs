defmodule Delivest.Oms.Orders.ScheduleGuardTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory

  alias Delivest.{LocalTime, Repo}
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.Orders.ScheduleGuard

  setup do
    Cachex.clear(:branch_cache)
    :ok
  end

  test "the same UTC moment can be open in one branch zone and closed in another" do
    moscow = branch_with(zone: "Europe/Moscow", hours: full_week())
    ekb = branch_with(zone: "Asia/Yekaterinburg", hours: every_day("09:00", "10:00"))

    # Tomorrow at 12:00 in Yekaterinburg is 10:00 in Moscow.
    at = tomorrow_at("12:00", "Asia/Yekaterinburg")

    assert :ok = ScheduleGuard.check(moscow.id, at)
    assert {:error, :cook_by_outside_hours} = ScheduleGuard.check(ekb.id, at)
  end

  test "a window that crosses midnight is open in the early morning" do
    branch = branch_with(zone: "Europe/Moscow", hours: every_day("22:00", "03:00"))
    at = tomorrow_at("01:00", "Europe/Moscow")

    assert :ok = ScheduleGuard.check(branch.id, at)
  end

  test "a date exception replaces the weekly schedule" do
    branch = branch_with(zone: "Europe/Moscow", hours: full_week())
    at = tomorrow_at("12:00", "Europe/Moscow")
    date = at |> DateTime.shift_zone!("Europe/Moscow") |> DateTime.to_date()

    update_info(branch, %{
      special_hours: %{Date.to_iso8601(date) => %{"enabled" => false}}
    })

    assert {:error, :cook_by_outside_hours} = ScheduleGuard.check(branch.id, at)
  end

  test "a manual pause rejects an otherwise valid future slot" do
    branch = branch_with(zone: "Europe/Moscow", hours: full_week())
    at = tomorrow_at("12:00", "Europe/Moscow")

    update_info(branch, %{
      intake: %{
        paused_until: DateTime.utc_now() |> DateTime.add(2, :hour) |> DateTime.truncate(:second),
        pause_reason: "Kitchen"
      }
    })

    assert {:error, {:branch_paused, %{mode: :paused}}} = ScheduleGuard.check(branch.id, at)
  end

  test "a time in the past is rejected" do
    branch = branch_with(zone: "Europe/Moscow", hours: full_week())
    at = DateTime.utc_now() |> DateTime.add(-5, :minute)

    assert {:error, :cook_by_in_past} = ScheduleGuard.check(branch.id, at)
  end

  test "a branch without its own zone uses the franchise one" do
    branch = branch_with(zone: nil, hours: full_week())
    at = tomorrow_at("12:00", "Europe/Moscow")

    assert LocalTime.timezone(branch.id) == "Europe/Moscow"
    assert :ok = ScheduleGuard.check(branch.id, at)
  end

  defp branch_with(opts) do
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      timezone: Keyword.get(opts, :zone),
      working_hours: Keyword.fetch!(opts, :hours),
      special_hours: Keyword.get(opts, :special_hours, %{})
    })

    Cachex.clear(:branch_cache)
    branch
  end

  defp update_info(branch, attrs) do
    info = Repo.get_by!(BranchInfo, branch_id: branch.id)

    changes = BranchInfo.changeset(info, attrs)

    changes =
      if Map.has_key?(attrs, :special_hours) do
        Ecto.Changeset.put_change(changes, :special_hours, attrs.special_hours)
      else
        changes
      end

    Repo.update!(changes)

    Cachex.clear(:branch_cache)
  end

  defp full_week, do: every_day("00:00", "23:59")

  defp every_day(open, close) do
    Map.new(
      ~w(monday tuesday wednesday thursday friday saturday sunday),
      &{&1, %{"enabled" => true, "open" => open, "close" => close}}
    )
  end

  defp tomorrow_at(time, zone) do
    date = LocalTime.today(zone) |> Date.add(1)
    LocalTime.naive_to_utc(NaiveDateTime.new!(date, Time.from_iso8601!(time <> ":00")), zone)
  end
end
