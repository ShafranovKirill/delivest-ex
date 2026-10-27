defmodule DelivestWeb.Client.BranchControllerTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Repo

  test "lists branches with their info", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    Repo.insert!(%BranchInfo{branch_id: branch.id, address: "ул Ленина, 1", city: "Тюмень"})

    data = conn |> get(~p"/client/branches") |> json_response(200) |> Map.fetch!("data")
    listed = Enum.find(data, &(&1["id"] == branch.id))

    assert %{"address" => "ул Ленина, 1", "city" => "Тюмень"} = listed["branch_info"]
  end
end
