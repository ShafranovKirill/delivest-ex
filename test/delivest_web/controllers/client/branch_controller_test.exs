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
      manual_rating: 4.5
    })

    data = conn |> get(~p"/client/branches") |> json_response(200) |> Map.fetch!("data")
    listed = Enum.find(data, &(&1["id"] == branch.id))

    assert %{"address" => "ул Ленина, 1", "city" => "Тюмень", "manual_rating" => 4.5} =
             listed["branch_info"]
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
