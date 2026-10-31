defmodule DelivestWeb.Client.LoyaltyControllerTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Loyalty
  alias Delivest.Repo
  alias DelivestWeb.ClientToken

  defp authed(client) do
    put_req_header(
      build_conn(),
      "authorization",
      "Bearer " <> ClientToken.issue(client.id).access_token
    )
  end

  setup do
    branch = insert(:branch, is_active: true)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      loyalty: %Delivest.Identity.Branch.LoyaltySettings{enabled: true, per_rubles: 100, stars: 5}
    })

    staff = insert(:staff, role: insert(:role, permissions: ["clients.update"]))
    insert(:staff_branch, staff: staff, branch: branch)
    %{branch: branch, client: insert(:client), staff: Repo.preload(staff, [:role, :branches])}
  end

  test "returns the balance and history in a branch with the program", ctx do
    {:ok, _entry} = Loyalty.adjust(ctx.staff, ctx.branch, ctx.client.id, 25, "welcome")

    data =
      ctx.client
      |> authed()
      |> get(~p"/client/loyalty?branch_id=#{ctx.branch.id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{"enabled" => true, "balance" => 25, "history" => [%{"amount" => 25}]} = data
  end

  test "hides the history where the program is off", ctx do
    other = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: other.id})

    data =
      ctx.client
      |> authed()
      |> get(~p"/client/loyalty?branch_id=#{other.id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{"enabled" => false, "history" => []} = data
  end

  test "needs a signed in client", ctx do
    assert build_conn() |> get(~p"/client/loyalty?branch_id=#{ctx.branch.id}") |> response(401)
  end

  test "the branch card tells the rate", ctx do
    info =
      build_conn()
      |> get(~p"/client/branches")
      |> json_response(200)
      |> Map.fetch!("data")
      |> Enum.find(&(&1["id"] == ctx.branch.id))
      |> get_in(["branch_info", "loyalty"])

    assert %{"enabled" => true, "per_rubles" => 100, "stars" => 5} = info
  end
end
