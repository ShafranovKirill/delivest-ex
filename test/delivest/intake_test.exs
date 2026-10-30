defmodule Delivest.IntakeTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Intake
  alias Delivest.Oms.OrderDeadline

  setup do
    branch = insert(:branch, is_active: true)
    Repo.insert!(%BranchInfo{branch_id: branch.id, delivery_time: 40})

    staff = insert(:staff, role: insert(:role, permissions: ["orders.update"]))
    insert(:staff_branch, staff: staff, branch: branch)
    %{branch: branch, staff: staff}
  end

  test "an untouched branch takes orders at the usual time", %{branch: branch} do
    assert %{mode: :normal, extra_minutes: 0} = Intake.status(branch.id)
    assert OrderDeadline.delivery_minutes(branch.id) == 40
  end

  test "load adds minutes to the time and ends by itself", %{branch: branch, staff: staff} do
    assert {:ok, %{mode: :load, extra_minutes: 20}} = Intake.start_load(staff, branch, 20, 30)
    assert OrderDeadline.delivery_minutes(branch.id) == 60

    later = DateTime.add(DateTime.utc_now(), 31, :minute)
    assert %{mode: :normal, extra_minutes: 0} = Intake.status(branch.id, later)
  end

  test "a pause closes the intake, keeps the reason and resumes", %{branch: branch, staff: staff} do
    assert {:ok, %{mode: :paused, reason: "нет курьеров"}} =
             Intake.pause(staff, branch, 30, "нет курьеров")

    refute Intake.accepting?(branch.id)

    assert {:ok, %{mode: :normal}} = Intake.resume(staff, branch)
    assert Intake.accepting?(branch.id)
  end

  test "a pause until the end of the day lasts past now", %{branch: branch, staff: staff} do
    assert {:ok, %{mode: :paused, until: until}} = Intake.pause(staff, branch, :end_of_day)
    assert DateTime.compare(until, DateTime.utc_now()) == :gt
  end

  test "staff without the permission cannot change the mode", %{branch: branch} do
    other = insert(:staff, role: insert(:role, permissions: ["orders.read"]))
    insert(:staff_branch, staff: other, branch: branch)
    assert {:error, :forbidden} = Intake.pause(other, branch, 15)
    assert Intake.accepting?(branch.id)
  end
end
