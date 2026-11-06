defmodule Delivest.Net.CatalogsTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory

  alias Delivest.Identity.Branch
  alias Delivest.Net.Catalogs

  test "a stale fill under an old catalog version is not served after invalidation" do
    branch = insert(:branch)
    old_version = Repo.get!(Branch, branch.id).catalog_version
    old_key = {:branch_catalog, branch.id, old_version}

    assert :ok = Catalogs.clear_menu_cache(branch.id)
    Cachex.put(:menu_cache, old_key, :stale)
    assert Repo.get!(Branch, branch.id).catalog_version == old_version + 1
    assert {:ok, menu} = Catalogs.get_menu_for_branch(branch.id)
    refute menu == :stale
  end

  test "cold cache and unavailable cache both build a menu" do
    branch = insert(:branch)
    assert {:ok, cold} = Catalogs.get_menu_for_branch(branch.id)

    assert :ok = Supervisor.terminate_child(Delivest.Supervisor, :menu_cache)
    on_exit(fn -> Supervisor.restart_child(Delivest.Supervisor, :menu_cache) end)

    assert {:ok, fallback} = Catalogs.get_menu_for_branch(branch.id)
    assert fallback == cold
  end

  test "unavailable stop cache falls back to branch rows" do
    branch = insert(:branch)
    product = insert_branch_product(branch.id)

    Repo.insert!(%Delivest.Net.ProductStop{
      branch_id: branch.id,
      product_id: product.id,
      source: "manual"
    })

    assert :ok = Supervisor.terminate_child(Delivest.Supervisor, :stop_cache)
    on_exit(fn -> Supervisor.restart_child(Delivest.Supervisor, :stop_cache) end)
    assert MapSet.member?(Delivest.Net.Stops.stopped_ids(branch.id), product.id)
  end

  test "compiled promo rules ignore an old fill and tolerate cache failure" do
    branch = insert(:branch)
    version = Repo.get!(Branch, branch.id).catalog_version
    Delivest.Promo.Catalog.invalidate(branch.id)
    Cachex.put(:promo_cache, {:compiled_promo, branch.id, version}, [:stale])
    assert Delivest.Promo.Catalog.list(branch.id) == []

    assert :ok = Supervisor.terminate_child(Delivest.Supervisor, :promo_cache)
    on_exit(fn -> Supervisor.restart_child(Delivest.Supervisor, :promo_cache) end)
    assert Delivest.Promo.Catalog.list(branch.id) == []
  end
end
