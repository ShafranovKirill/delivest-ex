defmodule DelivestWeb.Client.AllOptionalOffOrderTest do
  use DelivestWeb.ConnCase, async: false

  import Delivest.Factory

  alias Delivest.Features.{Gate, Registry}
  alias Delivest.Identity.Branch.{BranchInfo, PaymentSettings}
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Integrations.Frontpad
  alias Delivest.Oms.{Order, Orders}
  alias Delivest.Repo

  test "guest checkout and staff status progression work with every optional capability off", %{
    conn: conn
  } do
    branch = insert(:branch, is_active: true)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Frontpad.Settings{api_key: "key", affiliate: "3"}
      },
      payments: %PaymentSettings{cash: false, card_offline: false, online: true}
    })

    product = insert_branch_product(branch.id, price: 300)

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    for feature <- Registry.features(), scope_key <- ["franchise", "branch:" <> branch.id] do
      Repo.insert_all(
        Gate,
        [
          %{
            feature: feature,
            scope_key: scope_key,
            enabled: false,
            generation: 2,
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: [set: [enabled: false, generation: 2]],
        conflict_target: [:feature, :scope_key]
      )
    end

    conn =
      put_req_header(
        conn,
        "x-forwarded-for",
        "all-off-test-#{System.unique_integer([:positive])}"
      )

    selected = post(conn, ~p"/client/branches/#{branch.id}/select")
    assert %{"data" => %{"branch_info" => info}} = json_response(selected, 200)
    refute info["stocks_enabled"]
    refute info["promotions_enabled"]
    refute info["couriers_enabled"]
    assert info["payment_methods"] == ["cash"]

    conn = recycle_with_headers(selected)
    cart = conn |> get(~p"/client/cart?branch_id=#{branch.id}") |> json_response(200)
    cart_id = cart["data"]["id"]

    added = post(conn, ~p"/client/cart/#{cart_id}/items/#{product.id}")
    assert json_response(added, 200)["data"]["total_amount"] == 300

    body =
      added
      |> recycle_with_headers()
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
    assert body["data"]["total_amount"] == 300

    order = Repo.get!(Order, body["data"]["id"])
    assert order.crm == nil
    staff = insert(:staff, role: insert(:role, permissions: ["orders.update"]))
    insert(:staff_branch, staff: staff, branch: branch)
    staff = Repo.preload(staff, [:role, :branches])
    assert {:ok, accepted} = Orders.advance_order(order, :accepted, {:staff, staff})
    assert accepted.status == :accepted
    assert {:ok, completed} = Orders.advance_order(accepted, :completed, :system)
    assert completed.status == :completed
  end

  defp recycle_with_headers(conn) do
    forwarded = get_req_header(conn, "x-forwarded-for")
    conn |> recycle() |> put_req_header("x-forwarded-for", Enum.join(forwarded, ","))
  end
end
