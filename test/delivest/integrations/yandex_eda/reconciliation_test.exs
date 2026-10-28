defmodule Delivest.Integrations.YandexEda.ReconciliationTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Delivest.YandexEdaFixtures

  alias Delivest.Integrations.YandexEda
  alias Delivest.LocalTime

  setup do
    push_credentials()
    branch = yandex_branch()
    product = menu_product(branch, menu_category(branch))
    staff = insert(:staff, role: build(:role, permissions: ["orders.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    %{branch: branch, product: product, staff: staff}
  end

  defp order(branch, product) do
    params = order_params(branch, [product])
    {:ok, order} = YandexEda.create_order(params)
    {params["eatsId"], order}
  end

  defp remote(eats_id, status),
    do: %{"eats_id" => eats_id, "status" => status, "items_cost" => 300, "service" => "YE"}

  test "only differences between yandex and our orders are shown", %{
    branch: branch,
    product: product,
    staff: staff
  } do
    {fine, _} = order(branch, product)
    {cancelled, _} = order(branch, product)
    {delivered, delivered_order} = order(branch, product)
    {forgotten, _} = order(branch, product)

    delivered_order |> Ecto.Changeset.change(status: :cancelled) |> Repo.update!()

    stub_push(%{
      "/v1/orders-history" => %{
        "orders" => [
          remote(fine, "DELIVERED"),
          remote(cancelled, "CANCELLED"),
          remote(delivered, "DELIVERED"),
          remote("260427-unknown", "NEW")
        ]
      }
    })

    assert {:ok, %{total: 4, problems: problems}} =
             YandexEda.reconcile(staff, branch.id, LocalTime.today())

    assert Map.new(problems, &{&1.eats_id, &1.problem}) == %{
             cancelled => :cancelled_in_yandex,
             delivered => :cancelled_here,
             forgotten => :not_in_yandex,
             "260427-unknown" => :missing
           }

    assert_received {:push, "/v1/orders-history", filter}
    assert filter["origin_ids"] == [%{"origin_id" => branch.id}]
    assert filter["pagination"] == %{"limit" => 1000, "offset" => 0}
  end

  test "reconciliation needs the orders right", %{branch: branch} do
    assert {:error, :forbidden} =
             YandexEda.reconcile(insert(:staff), branch.id, LocalTime.today())
  end
end
