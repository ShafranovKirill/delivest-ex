defmodule Delivest.Integrations.Crm.AcceptPriceTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Ecto.Query

  alias Delivest.Audit
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.{AcceptPrice, BranchSettings, Catalog}
  alias Delivest.Integrations.Frontpad
  alias Delivest.Net.Products

  defp branch(key) do
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{provider: :frontpad, frontpad: %Frontpad.Settings{api_key: key}}
    })

    branch
  end

  defp staff(branch, permissions) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    staff
  end

  defp catalog(price) do
    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{
        "result" => "success",
        "product_id" => %{"0" => "42"},
        "name" => %{"0" => "Soup"},
        "price" => %{"0" => price}
      })
    end)
  end

  test "fresh CRM cents win over a stale snapshot and a retry has no side effects" do
    branch = branch("accept-key")
    product = insert_branch_product(branch.id, external_id: "42", price: 60_000)
    staff = staff(branch, ["products.update", "integrations.read"])
    catalog("600")
    assert {:ok, _} = Catalog.refresh(branch.id, :frontpad)

    assert Catalog.get_snapshot(branch.id, :frontpad).products |> hd() |> Map.fetch!("price") ==
             60_000

    catalog("650")
    Audit.subscribe()
    Products.subscribe_branch(branch.id)
    version = Repo.get!(Delivest.Identity.Branch, branch.id).catalog_version

    assert {:ok, updated, catalog} = AcceptPrice.run(staff, branch.id, product.id, 65_000)
    assert updated.price == 65_000
    assert Enum.any?(catalog, &(&1.price == 65_000))
    product_id = product.id
    assert Repo.get!(Delivest.Net.Product, product.id).price == 65_000
    assert Repo.get!(Delivest.Identity.Branch, branch.id).catalog_version == version + 1
    assert_receive {:audit_event, %{action: "product.updated", subject_id: ^product_id}}
    assert_receive {:product_updated, %{id: ^product_id}}
    assert_receive :catalog_changed

    assert {:ok, :unchanged, _catalog} = AcceptPrice.run(staff, branch.id, product.id, 65_000)
    assert Repo.get!(Delivest.Identity.Branch, branch.id).catalog_version == version + 1
    refute_receive {:audit_event, %{subject_id: ^product_id}}
    refute_receive {:product_updated, _}
  end

  test "stale expected CRM price does not update and returns the new price" do
    branch = branch("stale-key")
    product = insert_branch_product(branch.id, external_id: "42", price: 60_000)
    staff = staff(branch, ["products.update", "integrations.read"])
    catalog("650")

    assert {:error, {:price_changed, 65_000}} =
             AcceptPrice.run(staff, branch.id, product.id, 60_000)

    assert Repo.get!(Delivest.Net.Product, product.id).price == 60_000
  end

  test "permissions, branch mapping, and shared ownership reject without a CRM request" do
    branch = branch("guard-key")
    other = branch("other-key")
    product = insert_branch_product(branch.id, external_id: "42", price: 60_000)
    read_only = staff(branch, ["integrations.read"])
    no_crm_read = staff(branch, ["products.update"])
    allowed = staff(branch, ["products.update", "integrations.read"])
    Req.Test.stub(Delivest.HTTP.Client, fn _ -> flunk("CRM must not be called") end)

    assert {:error, :forbidden} = AcceptPrice.run(read_only, branch.id, product.id, 65_000)
    assert {:error, :forbidden} = AcceptPrice.run(no_crm_read, branch.id, product.id, 65_000)
    assert {:error, :forbidden} = AcceptPrice.run(allowed, other.id, product.id, 65_000)
    assert {:error, :invalid_id} = AcceptPrice.run(allowed, branch.id, "bad-id", 65_000)
    assert {:error, :invalid_id} = AcceptPrice.run(allowed, "bad-id", product.id, 65_000)

    {:ok, _} = Delivest.Relations.create_relation(Repo, "Branch", other.id, "Product", product.id)
    assert {:error, :shared_product} = AcceptPrice.run(allowed, branch.id, product.id, 65_000)
    assert Repo.get!(Delivest.Net.Product, product.id).price == 60_000
  end

  test "CRM fetch failure leaves price and catalog version unchanged" do
    branch = branch("failure-key")
    product = insert_branch_product(branch.id, external_id: "42", price: 60_000)
    staff = staff(branch, ["products.update", "integrations.read"])
    version = Repo.get!(Delivest.Identity.Branch, branch.id).catalog_version

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{"result" => "error", "error" => "offline"})
    end)

    assert {:error, _} = AcceptPrice.run(staff, branch.id, product.id, 65_000)
    assert Repo.get!(Delivest.Net.Product, product.id).price == 60_000
    assert Repo.get!(Delivest.Identity.Branch, branch.id).catalog_version == version
  end

  test "a mapping changed during the fresh fetch rejects the write" do
    branch = branch("mapping-key")
    product = insert_branch_product(branch.id, external_id: "42", price: 60_000)
    staff = staff(branch, ["products.update", "integrations.read"])

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Delivest.Repo.get_by!(Delivest.Net.ProductExternalId,
        entity_id: product.id,
        branch_id: branch.id,
        provider: "frontpad"
      )
      |> Ecto.Changeset.change(external_id: "43")
      |> Delivest.Repo.update!()

      Req.Test.json(conn, %{
        "result" => "success",
        "product_id" => %{"0" => "42"},
        "name" => %{"0" => "Soup"},
        "price" => %{"0" => "650"}
      })
    end)

    assert {:error, :mapping_changed} = AcceptPrice.run(staff, branch.id, product.id, 65_000)
    assert Repo.get!(Delivest.Net.Product, product.id).price == 60_000
  end

  test "malformed CRM price is rejected without changing the product" do
    branch = branch("invalid-price-key")
    product = insert_branch_product(branch.id, external_id: "42", price: 60_000)
    staff = staff(branch, ["products.update", "integrations.read"])
    catalog("unknown")

    assert {:error, :invalid_crm_price} = AcceptPrice.run(staff, branch.id, product.id, 65_000)
    assert Repo.get!(Delivest.Net.Product, product.id).price == 60_000
  end

  test "overlapping accepts under the SQL sandbox update and audit once" do
    branch = branch("concurrent-key")
    product = insert_branch_product(branch.id, external_id: "42", price: 60_000)
    staff = staff(branch, ["products.update", "integrations.read"])
    catalog("650")
    version = Repo.get!(Delivest.Identity.Branch, branch.id).catalog_version
    supervisor = start_supervised!(Task.Supervisor)

    results =
      1..2
      |> Enum.map(fn _ ->
        Task.Supervisor.async_nolink(supervisor, fn ->
          AcceptPrice.run(staff, branch.id, product.id, 65_000)
        end)
      end)
      |> Enum.map(&Task.await(&1, 10_000))

    assert Enum.count(results, &match?({:ok, %Delivest.Net.Product{}, _}, &1)) == 1
    assert Enum.count(results, &match?({:ok, :unchanged, _}, &1)) == 1
    assert Repo.get!(Delivest.Identity.Branch, branch.id).catalog_version == version + 1
    product_id = product.id

    assert Repo.aggregate(
             from(e in Delivest.Audit.Event,
               where: e.subject_id == ^product_id and e.action == "product.updated"
             ),
             :count
           ) == 1
  end
end
