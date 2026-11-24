defmodule DelivestWeb.Client.CrmDisabledOrderTest do
  use DelivestWeb.ConnCase, async: true
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory

  alias Delivest.Features
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.{BranchSettings, SyncWorker}
  alias Delivest.Integrations.Frontpad
  alias Delivest.Oms.Order
  alias Delivest.Repo

  test "guest checkout stays local when the configured CRM integration is off", %{conn: conn} do
    branch = insert(:branch, is_active: true)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        sources: ["app", "staff"],
        frontpad: %Frontpad.Settings{api_key: "key", affiliate: "3"}
      }
    })

    product = insert_branch_product(branch.id, price: 300, external_id: "fp-guest")

    assert {:ok, _} = Features.configure("integration_frontpad", :franchise, false, actor: "test")

    conn =
      put_req_header(
        conn,
        "x-forwarded-for",
        "crm-off-guest-#{System.unique_integer([:positive])}"
      )

    selected = post(conn, ~p"/client/branches/#{branch.id}/select")
    assert json_response(selected, 200)["data"]["id"] == branch.id

    conn =
      selected
      |> recycle()
      |> put_req_header(
        "x-forwarded-for",
        Enum.join(get_req_header(conn, "x-forwarded-for"), ",")
      )

    cart = conn |> get(~p"/client/cart?branch_id=#{branch.id}") |> json_response(200)
    cart_id = cart["data"]["id"]

    added = post(conn, ~p"/client/cart/#{cart_id}/items/#{product.id}")
    assert json_response(added, 200)["data"]["total_amount"] == 300

    body =
      added
      |> recycle()
      |> put_req_header(
        "x-forwarded-for",
        Enum.join(get_req_header(conn, "x-forwarded-for"), ",")
      )
      |> post(~p"/client/orders", %{
        "cart_id" => cart_id,
        "branch_id" => branch.id,
        "fulfillment_type" => "pickup",
        "payment_method" => "cash",
        "customer_phone" => "+79990001122",
        "customer_name" => "Иван"
      })
      |> json_response(200)

    assert body["data"]["status"] == "created"
    assert %Order{crm: nil} = Repo.get!(Order, body["data"]["id"])
    refute_enqueued(worker: SyncWorker)
  end
end
