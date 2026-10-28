defmodule Delivest.Oms.OrderSourceTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Integrations.Frontpad
  alias Delivest.Oms
  alias Delivest.Oms.{Carts, Order}

  defp branch(crm \\ nil) do
    branch = insert(:branch, is_active: true)
    if crm, do: Repo.insert!(%BranchInfo{branch_id: branch.id, crm: crm})
    branch
  end

  defp order(branch, attrs \\ %{}, opts \\ []) do
    product = insert_branch_product(branch.id, price: 100)

    {:ok, cart} =
      Carts.create_cart(%{session_id: "src-#{Ecto.UUID.generate()}", branch_id: branch.id})

    {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)

    %{
      "cart_id" => cart.id,
      "branch_id" => branch.id,
      "fulfillment_type" => "pickup",
      "payment_method" => "cash"
    }
    |> Map.merge(attrs)
    |> Oms.create_order(opts)
  end

  test "the source comes from the server, never from the request" do
    branch = branch()

    assert {:ok, %Order{source: "app"}} = order(branch, %{"source" => "staff"})
    assert {:ok, %Order{source: "staff"}} = order(branch, %{}, source: "staff")
  end

  test "an unknown source is rejected" do
    assert {:error, :order, changeset} = order(branch(), %{}, source: "nowhere")
    assert %{source: ["is invalid"]} = errors_on(changeset)
  end

  test "a channel order id is accepted once" do
    branch = branch()
    channel = %{provider: "test", external_id: "260423-SE1"}

    assert {:ok, %Order{channel: %{external_id: "260423-SE1"}}} =
             order(branch, %{}, channel: channel)

    assert {:error, :order, changeset} = order(branch, %{}, channel: channel)
    assert %{channel: [_taken]} = errors_on(changeset)
  end

  test "only allowed sources go to the crm" do
    crm = %BranchSettings{
      enabled: true,
      provider: :frontpad,
      sources: ["app"],
      frontpad: %Frontpad.Settings{api_key: "key", webhook_token: "t"}
    }

    branch = branch(crm)

    assert {:ok, %Order{status: :created, crm: %{provider: "frontpad"}}} = order(branch)
    assert {:ok, %Order{status: :created, crm: nil}} = order(branch, %{}, source: "staff")
  end
end
