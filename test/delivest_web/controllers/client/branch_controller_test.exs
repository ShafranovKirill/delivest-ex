defmodule DelivestWeb.Client.BranchControllerTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Repo

  test "lists branches with their info", %{conn: conn} do
    branch = insert(:branch, is_active: true)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      address: "ул Ленина, 1",
      city: "Тюмень",
      manual_rating: 4.5,
      timezone: "Asia/Yekaterinburg"
    })

    data = conn |> get(~p"/client/branches") |> json_response(200) |> Map.fetch!("data")
    listed = Enum.find(data, &(&1["id"] == branch.id))

    assert %{
             "address" => "ул Ленина, 1",
             "city" => "Тюмень",
             "manual_rating" => 4.5,
             "timezone" => "Asia/Yekaterinburg"
           } = listed["branch_info"]
  end

  test "pixel config belongs only to its enabled branch", %{conn: conn} do
    active = insert(:branch, is_active: true)
    other = insert(:branch, is_active: true)
    disabled = insert(:branch, is_active: true)

    for {branch, enabled, id} <- [
          {active, true, "3817108"},
          {other, true, "7654321"},
          {disabled, false, "88888"}
        ] do
      %BranchInfo{branch_id: branch.id}
      |> BranchInfo.changeset(%{
        vk_ads: %{enabled: enabled, counter_id: id, privacy_approved: true}
      })
      |> Repo.insert!()
    end

    data = conn |> get(~p"/client/branches") |> json_response(200) |> Map.fetch!("data")
    by_id = Map.new(data, &{&1["id"], &1["branch_info"]["vk_ads"]})
    assert by_id[active.id] == %{"enabled" => true, "counter_id" => "3817108"}
    assert by_id[other.id] == %{"enabled" => true, "counter_id" => "7654321"}
    assert by_id[disabled.id] == %{"enabled" => false, "counter_id" => nil}
  end

  test "publishes enabled fulfillment methods with backward compatible defaults", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    info = Repo.insert!(%BranchInfo{branch_id: branch.id})
    data = conn |> get(~p"/client/branches") |> json_response(200)

    assert Enum.find(data["data"], &(&1["id"] == branch.id))["branch_info"]["fulfillment_methods"] ==
             ["delivery", "pickup", "dine_in"]

    info
    |> BranchInfo.changeset(%{fulfillment: %{delivery: false, pickup: false, dine_in: true}})
    |> Repo.update!()

    Cachex.clear(:branch_cache)
    data = conn |> recycle() |> get(~p"/client/branches") |> json_response(200)

    assert Enum.find(data["data"], &(&1["id"] == branch.id))["branch_info"]["fulfillment_methods"] ==
             ["dine_in"]
  end
end
