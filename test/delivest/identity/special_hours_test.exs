defmodule Delivest.Identity.SpecialHoursTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Identity
  alias Delivest.Identity.Branch.BranchInfo

  setup do
    branch = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id})
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    %{branch: branch, staff: staff}
  end

  test "an exception overrides a date and past dates are dropped", %{branch: branch, staff: staff} do
    soon = Date.add(Date.utc_today(), 3)
    past = Date.add(Date.utc_today(), -5)

    Repo.update_all(BranchInfo,
      set: [special_hours: %{Date.to_iso8601(past) => %{"enabled" => false}}]
    )

    assert {:ok, %{info: info}} =
             Identity.set_special_day(staff, branch, soon, %{"enabled" => false})

    assert info.special_hours == %{
             Date.to_iso8601(soon) => %{"enabled" => false, "open" => nil, "close" => nil}
           }
  end

  test "working time is validated and removal works", %{branch: branch, staff: staff} do
    soon = Date.add(Date.utc_today(), 3)

    assert {:error, :invalid_time} =
             Identity.set_special_day(staff, branch, soon, %{
               "enabled" => true,
               "open" => "25:00",
               "close" => "18:00"
             })

    {:ok, _} =
      Identity.set_special_day(staff, branch, soon, %{
        "enabled" => true,
        "open" => "10:00",
        "close" => "18:00"
      })

    assert {:ok, %{info: %{special_hours: hours}}} =
             Identity.remove_special_day(staff, branch, soon)

    assert hours == %{}
  end

  test "staff without the right cannot change them", %{branch: branch} do
    other = insert(:staff, role: insert(:role, permissions: ["orders.read"]))

    assert {:error, :forbidden} =
             Identity.set_special_day(other, branch, Date.utc_today(), %{"enabled" => false})
  end
end
