defmodule Delivest.Integrations.Crm.CatalogTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import ExUnit.CaptureLog

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.{BranchSettings, Catalog}
  alias Delivest.Integrations.Frontpad

  defp branch(enabled?, api_key, name \\ "Center #{System.unique_integer([:positive])}") do
    branch = insert(:branch, name: name)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: enabled?,
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

  test "reports differences once and keeps the snapshot" do
    branch = branch(true, "key-a", "Center")
    insert_branch_product(branch.id, name: "Soup", external_id: "1", price: 100)
    insert_branch_product(branch.id, name: "Pizza", external_id: "2", price: 600)
    stub_catalog()

    log = capture_log(&Catalog.check_all/0)

    assert log =~
             "Frontpad · Center: product «Pizza» with CRM ID 2 costs 600 ₽ in the app and 650 ₽ in Frontpad"

    snapshot = Catalog.get_snapshot(branch.id)
    assert length(snapshot.products) == 2
    assert [%{"type" => "price_mismatch"}] = snapshot.issues

    refute capture_log(&Catalog.check_all/0) =~ "Pizza"
  end

  test "branches sharing an account fetch the catalog once" do
    branch(true, "key-b")
    branch(true, "key-b")
    stub_catalog()

    Catalog.check_all()

    assert_received :catalog_requested
    refute_received :catalog_requested
  end

  test "branches without crm mode are skipped" do
    branch = branch(false, "key-c")
    stub_catalog()

    Catalog.check_all()

    refute_received :catalog_requested
    assert Catalog.get_snapshot(branch.id) == nil
  end
end
