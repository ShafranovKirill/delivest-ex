defmodule Delivest.Integrations.YandexEda.PauseTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Delivest.YandexEdaFixtures

  alias Delivest.Integrations.YandexEda

  setup do
    push_credentials()
    branch = insert(:branch)
    staff = insert(:staff, role: build(:role, permissions: ["stops.update"]))
    insert(:staff_branch, staff: staff, branch: branch)
    %{staff: staff, branch: branch}
  end

  test "a pause blocks both delivery types until the end", %{staff: staff, branch: branch} do
    stub_push(%{})

    assert {:ok, _} = YandexEda.pause(staff, branch.id, 30, "too_busy")

    assert_received {:push, "/block", body}

    assert body["vendorInfo"] == [
             %{"vendorId" => branch.id, "deliveryType" => "ddc"},
             %{"vendorId" => branch.id, "deliveryType" => "marketplace"}
           ]

    assert %{"tag" => "too_busy", "from" => from, "to" => to} = body
    {:ok, from, _} = DateTime.from_iso8601(from)
    {:ok, to, _} = DateTime.from_iso8601(to)
    assert DateTime.diff(to, from, :minute) == 30
  end

  test "a pause without duration has no end", %{staff: staff, branch: branch} do
    stub_push(%{})

    assert {:ok, _} = YandexEda.pause(staff, branch.id, nil, "technical_problem")
    assert_received {:push, "/block", body}
    refute Map.has_key?(body, "to")
  end

  test "active pauses are listed once and lifted", %{staff: staff, branch: branch} do
    block = %{
      "vendorId" => branch.id,
      "blockId" => "42",
      "deliveryType" => "ddc",
      "from" => "2026-10-27T12:00:00+03:00",
      "to" => "2026-10-27T12:30:00+03:00",
      "source" => "delivest",
      "availableToCancel" => true
    }

    stub_push(%{
      "/v2/status" => %{"items" => [block, %{block | "deliveryType" => "marketplace"}]}
    })

    assert {:ok, [%{id: "42", from: ~N[2026-10-27 12:00:00], cancelable: true}]} =
             YandexEda.pauses(branch.id)

    assert_received {:push, "/v2/status", %{"statuses" => ["enabled"]}}

    assert {:ok, _} = YandexEda.resume(staff, branch.id, ["42"])
    assert_received {:push, "/unblock", %{"blockIds" => ["42"]}}
  end

  test "only branch editors pause and an unknown reason is refused", %{
    staff: staff,
    branch: branch
  } do
    assert {:error, :forbidden} = YandexEda.pause(insert(:staff), branch.id, 30, "too_busy")
    assert {:error, :forbidden} = YandexEda.resume(insert(:staff), branch.id, ["42"])
    assert {:error, :invalid_tag} = YandexEda.pause(staff, branch.id, 30, "lunch")
  end

  test "without push access there are no pauses", %{staff: staff, branch: branch} do
    Repo.delete_all(YandexEda.Settings)
    refute YandexEda.push_available?()
    assert {:error, :push_not_configured} = YandexEda.pause(staff, branch.id, 30, "too_busy")
  end
end
