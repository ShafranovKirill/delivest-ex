defmodule Delivest.Integrations.Crm.StopSyncTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.{BranchSettings, StopSync}
  alias Delivest.Integrations.Frontpad
  alias Delivest.Net.Stops

  defp branch(sync_stops?) do
    branch = insert(:branch, is_active: true)

    crm = %BranchSettings{
      enabled: true,
      provider: :frontpad,
      frontpad: %Frontpad.Settings{api_key: "key", sync_stops: sync_stops?}
    }

    info = Repo.insert!(%BranchInfo{branch_id: branch.id, crm: crm})
    {branch, info}
  end

  defp stub_stops(response),
    do: Req.Test.stub(Delivest.HTTP.Client, &Req.Test.json(&1, response))

  defp stops(ids),
    do: %{
      "result" => "success",
      "product_id" => Map.new(Enum.with_index(ids), fn {id, i} -> {to_string(i), id} end)
    }

  test "linked crm stops reach the branch and unlinked ones are reported" do
    {branch, _info} = branch(true)
    soup = insert_branch_product(branch.id, name: "Soup", external_id: "101")
    insert_branch_product(branch.id, name: "Tea", external_id: "102")

    stub_stops(stops(["101", "999"]))

    assert {:ok, %{stopped: 1, unlinked: ["999"]}} = StopSync.sync(branch.id)
    assert Stops.stopped_ids(branch.id) == MapSet.new([soup.id])
    assert %{unlinked: ["999"]} = StopSync.last(branch.id)
  end

  test "an empty stop list clears previous crm stops" do
    {branch, _info} = branch(true)
    soup = insert_branch_product(branch.id, external_id: "101")
    {:ok, _} = Stops.replace_external(branch.id, :frontpad, [soup.id])

    stub_stops(%{"result" => "success", "error" => "no_stops"})

    assert {:ok, %{stopped: 0}} = StopSync.sync(branch.id)
    assert Stops.stopped_ids(branch.id) == MapSet.new()
  end

  test "a failing crm keeps the last known stops" do
    {branch, _info} = branch(true)
    soup = insert_branch_product(branch.id, external_id: "101")
    {:ok, _} = Stops.replace_external(branch.id, :frontpad, [soup.id])

    stub_stops(%{"result" => "error", "error" => "requests_limit"})

    assert {:error, {:frontpad, "requests_limit"}} = StopSync.sync(branch.id)
    assert Stops.stopped_ids(branch.id) == MapSet.new([soup.id])
  end

  test "turning the option off removes crm stops" do
    {branch, _info} = branch(false)
    soup = insert_branch_product(branch.id, external_id: "101")
    {:ok, _} = Stops.replace_external(branch.id, :frontpad, [soup.id])

    assert {:ok, :disabled} = StopSync.sync(branch.id)
    assert Stops.stopped_ids(branch.id) == MapSet.new()
  end
end
