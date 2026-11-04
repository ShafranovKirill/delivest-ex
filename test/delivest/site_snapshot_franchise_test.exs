defmodule Delivest.SiteSnapshotFranchiseTest do
  use Delivest.DataCase, async: false

  import Ecto.Query
  import Delivest.Factory

  alias Delivest.{Relations, Repo, SiteSnapshot}
  alias Delivest.Franchise.{Documents, LegalDocument}
  alias Delivest.Franchise.Settings, as: FranchiseSettings
  alias Delivest.Identity.Branch
  alias Delivest.Identity.Branch.{BranchInfo, YcartSettings}
  alias Delivest.Integrations.Yookassa
  alias Delivest.Net.{Category, Product}
  alias Delivest.Relations.EntityRelation

  setup do
    %{staff: insert(:staff, role: insert(:role, permissions: ["admin"]))}
  end

  test "exports and imports the whole franchise with every section", %{staff: staff} do
    main = insert(:branch, name: "Main", slug: "main", code: "MAIN")
    north = insert(:branch, name: "North", slug: "north", code: "NORTH")
    extra = insert(:branch, name: "Extra", slug: "extra", code: "EXTRA")

    Repo.insert!(%BranchInfo{
      branch_id: main.id,
      timezone: "Asia/Yekaterinburg",
      ycart_settings: %YcartSettings{enabled: true, yandex_org_id: "org-1"}
    })

    Repo.insert!(%BranchInfo{branch_id: north.id, timezone: "Europe/Moscow"})

    category = insert(:category, name: "Pizza")
    product = insert(:product, name: "Margherita", category_id: category.id, price: 50_000)
    relate!(main, "Category", category.id)
    relate!(main, "Product", product.id)

    franchise = Repo.one(FranchiseSettings) || Repo.insert!(%FranchiseSettings{name: "Brand"})

    franchise
    |> Ecto.Changeset.change(name: "Brand", phone: "+79990000000")
    |> Repo.update!()

    assert {:ok, _} = Documents.save(:privacy, "Our privacy")
    assert {:ok, _} = Documents.save(:offer, "Our offer")

    Repo.insert!(%Yookassa.Settings{
      shop_id: "123456",
      secret_key: "secret",
      webhook_token: "token-123"
    })

    assert {:ok, archive} =
             SiteSnapshot.export_franchise(
               staff,
               [:storefront, :catalog, :franchise, :integrations]
             )

    Enum.each([main, north, extra], &delete_branch!/1)
    Repo.delete_all(Yookassa.Settings)
    Repo.delete_all(LegalDocument)
    franchise |> Ecto.Changeset.change(name: "Old brand") |> Repo.update!()

    assert {:ok, counts} = SiteSnapshot.import_franchise(staff, archive)
    assert counts.branches_created == 3
    assert counts.branches_updated == 0
    assert counts.products == 1
    assert counts.categories == 1

    main = Repo.get_by!(Branch, slug: "main")
    north = Repo.get_by!(Branch, slug: "north")

    assert main.name == "Main"
    assert north.name == "North"
    assert Repo.get_by!(Branch, slug: "extra").name == "Extra"

    assert Repo.get_by!(BranchInfo, branch_id: main.id).timezone == "Asia/Yekaterinburg"
    assert Repo.get_by!(BranchInfo, branch_id: north.id).timezone == "Europe/Moscow"

    ycart = Repo.get_by!(BranchInfo, branch_id: main.id).ycart_settings
    assert ycart.enabled
    assert ycart.yandex_org_id == "org-1"

    assert Repo.one!(FranchiseSettings).name == "Brand"
    assert Documents.get(:privacy).body == "Our privacy"
    assert Documents.get(:offer).body == "Our offer"
    assert Repo.one!(Yookassa.Settings).shop_id == "123456"

    assert [imported_product_id] = Relations.list_target_ids("Branch", main.id, "Product")
    imported_product = Repo.get!(Product, imported_product_id)
    assert imported_product.price == 50_000
    assert Relations.related?("Branch", main.id, "Product", imported_product.id)

    assert [imported_category_id] = Relations.list_target_ids("Branch", main.id, "Category")
    assert Repo.get!(Category, imported_category_id).name == "Pizza"

    refute Relations.related?("Branch", north.id, "Product", imported_product.id)
  end

  test "updates branches matched by slug, creates missing ones and keeps the rest", %{
    staff: staff
  } do
    main = insert(:branch, name: "Main", slug: "main", code: "MAIN")
    north = insert(:branch, name: "North", slug: "north", code: "NORTH")

    assert {:ok, archive} = SiteSnapshot.export_franchise(staff, [:franchise])

    _extra = insert(:branch, name: "Extra", slug: "extra", code: "EXTRA")
    main |> Branch.changeset(%{name: "Main changed"}) |> Repo.update!()
    delete_branch!(north)

    assert {:ok, counts} = SiteSnapshot.import_franchise(staff, archive)
    assert counts.branches_updated == 1
    assert counts.branches_created == 1

    assert Repo.get_by!(Branch, slug: "main").name == "Main"
    assert Repo.get_by!(Branch, slug: "north").name == "North"
    assert Repo.get_by!(Branch, slug: "extra").name == "Extra"
  end

  test "re-import is idempotent and does not duplicate catalog records", %{staff: staff} do
    main = insert(:branch, name: "Main", slug: "main", code: "MAIN")
    category = insert(:category)
    product = insert(:product, category_id: category.id)

    relate!(main, "Category", category.id)
    relate!(main, "Product", product.id)

    assert {:ok, archive} = SiteSnapshot.export_franchise(staff, [:catalog, :franchise])

    assert {:ok, %{branches_created: 0, branches_updated: 1, products: 1}} =
             SiteSnapshot.import_franchise(staff, archive)

    assert {:ok, %{branches_created: 0, branches_updated: 1, products: 1}} =
             SiteSnapshot.import_franchise(staff, archive)

    assert Repo.aggregate(Branch, :count) == 1
    assert Repo.aggregate(Product, :count) == 1
    assert Repo.aggregate(Category, :count) == 1
  end

  test "requires an admin and rejects a single-branch archive", %{staff: staff} do
    branch = insert(:branch)
    reader = insert(:staff, role: insert(:role, permissions: ["branches.read"]))

    assert {:error, :forbidden} = SiteSnapshot.export_franchise(reader, [:franchise])
    assert {:ok, branch_archive} = SiteSnapshot.export(staff, branch.id)
    assert {:error, :invalid_archive} = SiteSnapshot.import_franchise(staff, branch_archive)
  end

  test "rejects a franchise archive that declares an unknown section", %{staff: staff} do
    branch = insert(:branch)
    assert {:ok, archive} = SiteSnapshot.export_franchise(staff, [:franchise])
    {:ok, files} = :zip.extract(archive, [:memory])

    data =
      files
      |> Enum.find_value(fn
        {~c"data.json", body} -> Jason.decode!(body)
        _ -> nil
      end)
      |> Map.put("sections", ["franchise", "unknown"])

    body = Jason.encode!(data)

    files =
      Enum.map(files, fn
        {~c"data.json", _} ->
          {~c"data.json", body}

        {~c"manifest.json", manifest} ->
          value =
            manifest
            |> Jason.decode!()
            |> Map.put("sections", data["sections"])
            |> Map.put("data_size", byte_size(body))
            |> Map.put("data_sha256", :crypto.hash(:sha256, body) |> Base.encode16(case: :lower))

          {~c"manifest.json", Jason.encode!(value)}

        other ->
          other
      end)

    {:ok, {_, changed}} = :zip.create(~c"changed.zip", files, [:memory, {:uncompress, :all}])

    assert {:error, :invalid_archive} = SiteSnapshot.import_franchise(staff, changed)
    assert Repo.get!(Branch, branch.id).name == branch.name
  end

  defp relate!(branch, type, id) do
    assert {:ok, _} = Relations.create_relation(Repo, "Branch", branch.id, type, id)
  end

  defp delete_branch!(branch) do
    Repo.delete_all(from r in EntityRelation, where: r.from_id == ^branch.id)
    Repo.delete_all(from i in BranchInfo, where: i.branch_id == ^branch.id)
    Repo.delete!(branch)
  end
end
