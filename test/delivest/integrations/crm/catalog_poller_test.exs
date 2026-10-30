defmodule Delivest.Integrations.Crm.CatalogPollerTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.{BranchSettings, CatalogPoller, CatalogSnapshot}
  alias Delivest.Integrations.{Frontpad, Health}

  defp branch do
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Frontpad.Settings{api_key: "key-#{branch.id}", webhook_token: "t-#{branch.id}"}
      }
    })

    branch
  end

  defp stub_catalog(price) do
    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{
        "result" => "success",
        "product_id" => %{"0" => "1"},
        "name" => %{"0" => "Soup"},
        "price" => %{"0" => price}
      })
    end)
  end

  test "targets are the branches with Frontpad" do
    branch = branch()
    assert branch.id in CatalogPoller.targets()
  end

  test "a mismatch raises the integration warning and the fix removes it" do
    branch = branch()
    insert_branch_product(branch.id, name: "Soup", external_id: "1", price: 10_000)
    stub_catalog("150")

    assert :done = CatalogPoller.poll(branch.id)
    assert %{status: :warning, message: "catalog_issues:1"} = Health.get(:frontpad, branch.id)

    Repo.update_all(CatalogSnapshot,
      set: [checked_at: DateTime.add(DateTime.utc_now(), -2, :hour)]
    )

    stub_catalog("100")

    assert :done = CatalogPoller.poll(branch.id)
    assert %{status: :ok} = Health.get(:frontpad, branch.id)
  end

  test "a refresh inside the rate limit does nothing" do
    branch = branch()
    insert_branch_product(branch.id, name: "Soup", external_id: "1", price: 10_000)
    stub_catalog("100")

    assert :done = CatalogPoller.poll(branch.id)
    assert :done = CatalogPoller.poll(branch.id)
  end
end
