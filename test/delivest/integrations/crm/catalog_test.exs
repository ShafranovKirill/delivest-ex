defmodule Delivest.Integrations.Crm.CatalogTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.{BranchSettings, Catalog, CatalogSnapshot}
  alias Delivest.Integrations.Frontpad

  defp branch(api_key) do
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: false,
        provider: :frontpad,
        frontpad: %Frontpad.Settings{api_key: api_key}
      }
    })

    branch
  end

  defp stub_catalog do
    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      send(test_pid, :catalog_requested)

      Req.Test.json(conn, %{
        "result" => "success",
        "product_id" => %{"0" => "1", "1" => "2"},
        "name" => %{"0" => "Soup", "1" => "Pizza"},
        "price" => %{"0" => "100", "1" => "650"}
      })
    end)
  end

  test "refresh saves the catalog and the check compares it with the menu" do
    branch = branch("key-a")
    insert_branch_product(branch.id, name: "Soup", external_id: "1", price: 100)
    insert_branch_product(branch.id, name: "Pizza", external_id: "2", price: 600)
    insert_branch_product(branch.id, name: "Tea", external_id: "9", price: 50)
    stub_catalog()

    assert {:ok, snapshot} = Catalog.refresh(branch.id, :frontpad)
    assert length(snapshot.products) == 2
    assert Catalog.get_snapshot(branch.id, :frontpad).id == snapshot.id

    assert [
             %{type: :price_mismatch, name: "Pizza", crm_price: 650},
             %{type: :missing_in_crm, name: "Tea"}
           ] = Enum.sort_by(Catalog.issues(branch.id, snapshot), & &1.name)
  end

  test "refresh is allowed once per hour" do
    branch = branch("key-b")
    stub_catalog()

    assert {:ok, snapshot} = Catalog.refresh(branch.id, :frontpad)
    assert_received :catalog_requested

    assert {:error, {:too_early, available_at}} = Catalog.refresh(branch.id, :frontpad)
    assert available_at == DateTime.add(snapshot.checked_at, 3600)
    refute_received :catalog_requested

    snapshot
    |> Ecto.Changeset.change(checked_at: DateTime.add(DateTime.utc_now(:second), -3601))
    |> Repo.update!()

    assert {:ok, %CatalogSnapshot{}} = Catalog.refresh(branch.id, :frontpad)
    assert_received :catalog_requested
  end

  test "refresh without an api key does not call frontpad" do
    branch = branch(nil)
    stub_catalog()

    assert {:error, :missing_api_key} = Catalog.refresh(branch.id, :frontpad)
    refute_received :catalog_requested
    assert Catalog.get_snapshot(branch.id, :frontpad) == nil
  end
end
