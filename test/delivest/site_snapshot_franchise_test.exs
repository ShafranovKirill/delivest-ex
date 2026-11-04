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
  alias Delivest.Net.{Category, Product, ProductModifierGroup}
  alias Delivest.Relations.EntityRelation
  alias Delivest.SiteSnapshot.{Installation, Mapping}

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

  test "shares catalog records between branches and keeps target ids on re-import", %{
    staff: staff
  } do
    store = start_s3!()
    source_bucket = Delivest.Media.public_bucket()
    main = insert(:branch, name: "Main", slug: "main", code: "MAIN")
    north = insert(:branch, name: "North", slug: "north", code: "NORTH")
    category = insert(:category, name: "Pizza")
    tag = Repo.insert!(%Delivest.Net.ProductTag{name: "Hot"})

    product =
      insert(:product,
        name: "Margherita",
        category_id: category.id,
        price: 50_000,
        tags: [tag.id]
      )

    photo = Delivest.S3Stub.png(2, 2)

    media =
      Repo.insert!(%Delivest.Media.File{
        bucket: source_bucket,
        key: "products/shared.png",
        original_name: "shared.png",
        mime_type: "image/png",
        size: byte_size(photo),
        context: :product,
        owner_id: product.id
      })

    product |> Ecto.Changeset.change(media_id: media.id) |> Repo.update!()
    group = Repo.insert!(%Delivest.Net.ModifierGroup{name: "Extras"})
    Repo.insert!(%Delivest.Net.Modifier{group_id: group.id, name: "Cheese", price: 100})
    Repo.insert!(%ProductModifierGroup{product_id: product.id, group_id: group.id})

    relate!(main, "Category", category.id)
    relate!(main, "Product", product.id)
    relate!(north, "Category", category.id)
    relate!(north, "Product", product.id)

    Agent.update(store, &Map.put(&1, "/#{source_bucket}/products/shared.png", photo))

    assert {:ok, archive} = SiteSnapshot.export_franchise(staff, [:catalog, :franchise])
    clear_franchise!()
    use_bucket!("target-bucket")

    assert {:ok, counts} = SiteSnapshot.import_franchise(staff, archive)
    assert counts.branches_created == 2
    assert counts.products == 1
    assert counts.categories == 1
    assert counts.groups == 1
    assert counts.modifiers == 1
    assert counts.media == 1
    assert counts.tags == 1

    main = Repo.get_by!(Branch, slug: "main")
    north = Repo.get_by!(Branch, slug: "north")
    assert [product_id] = Relations.list_target_ids("Branch", main.id, "Product")
    assert product_id == product.id
    assert [^product_id] = Relations.list_target_ids("Branch", north.id, "Product")
    assert Repo.get!(Product, product_id).price == 50_000
    assert Repo.get!(Product, product_id).media_id == media.id
    assert Repo.get!(Delivest.Media.File, media.id).bucket == "target-bucket"

    assert_receive {:uploaded, "/target-bucket/site-snapshot/" <> _}
    objects = Agent.get(store, &map_size/1)

    assert {:ok, %{branches_created: 0, branches_updated: 2, products: 1}} =
             SiteSnapshot.import_franchise(staff, archive)

    assert Repo.get!(Product, product_id).price == 50_000
    assert map_size(Agent.get(store, & &1)) == objects
    refute_received {:uploaded, _}
  end

  test "applies integrations and franchise sections independently", %{staff: staff} do
    source = insert(:branch, name: "Source", slug: "source", code: "SRC")
    insert(:branch, name: "Target", slug: "target", code: "TGT")

    source_franchise =
      Repo.one(FranchiseSettings) || Repo.insert!(%FranchiseSettings{name: "Source"})

    source_franchise
    |> Ecto.Changeset.change(
      name: "Source brand",
      phone: "+79990000001",
      yandex_org_id: "source-org",
      yandex_api_key: "source-key"
    )
    |> Repo.update!()

    Repo.insert!(%Delivest.Integrations.Yookassa.Settings{
      shop_id: "111111",
      secret_key: "source-secret",
      webhook_token: "source-token"
    })

    assert {:ok, _} = Documents.save(:privacy, "Source privacy")

    assert {:ok, integrations} = SiteSnapshot.export_franchise(staff, [:integrations])
    assert {:ok, franchise} = SiteSnapshot.export_franchise(staff, [:franchise])

    source_franchise
    |> Ecto.Changeset.change(
      name: "Target brand",
      phone: "+79990000002",
      yandex_org_id: "target-org",
      yandex_api_key: "target-key"
    )
    |> Repo.update!()

    Repo.delete_all(Delivest.Integrations.Yookassa.Settings)

    Repo.insert!(%Delivest.Integrations.Yookassa.Settings{
      shop_id: "222222",
      secret_key: "target-secret",
      webhook_token: "target-token"
    })

    assert {:ok, _} = Documents.save(:privacy, "Target privacy")

    assert {:ok, _} =
             SiteSnapshot.import_franchise(staff, integrations)

    imported = Repo.one!(FranchiseSettings)
    assert imported.name == "Target brand"
    assert imported.phone == "+79990000002"
    assert imported.yandex_org_id == "source-org"
    assert imported.yandex_api_key == "source-key"
    assert Repo.one!(Delivest.Integrations.Yookassa.Settings).shop_id == "111111"
    assert Documents.get(:privacy).body == "Target privacy"
    assert Repo.get!(Branch, source.id).name == "Source"

    assert {:ok, _} =
             SiteSnapshot.import_franchise(staff, franchise)

    assert Repo.one!(FranchiseSettings).name == "Source brand"
    assert Repo.one!(FranchiseSettings).yandex_org_id == "source-org"
    assert Repo.one!(Delivest.Integrations.Yookassa.Settings).shop_id == "111111"
    assert Documents.get(:privacy).body == "Source privacy"
  end

  test "keeps one branch mapping per source installation", %{staff: staff} do
    branch = insert(:branch, name: "Main", slug: "main", code: "MAIN")
    assert {:ok, first_archive} = SiteSnapshot.export_franchise(staff, [:franchise])
    assert {:ok, _} = SiteSnapshot.import_franchise(staff, first_archive)

    installation = Repo.one!(Installation)
    installation |> Ecto.Changeset.change(installation_id: Ecto.UUID.generate()) |> Repo.update!()

    assert {:ok, second_archive} = SiteSnapshot.export_franchise(staff, [:franchise])
    assert {:ok, _} = SiteSnapshot.import_franchise(staff, second_archive)

    branch |> Ecto.Changeset.change(slug: "renamed") |> Repo.update!()
    assert {:ok, %{branches_created: 0}} = SiteSnapshot.import_franchise(staff, first_archive)
    assert Repo.get!(Branch, branch.id).slug == "main"
    assert Repo.aggregate(from(m in Mapping, where: m.entity_type == "branches"), :count) == 2
  end

  test "rejects a franchise archive at the branch entry point", %{staff: staff} do
    branch = insert(:branch)
    assert {:ok, archive} = SiteSnapshot.export_franchise(staff, [:franchise])
    assert {:error, :invalid_archive} = SiteSnapshot.import(staff, branch.id, archive)
  end

  defp start_s3! do
    store = start_supervised!({Agent, fn -> %{} end})
    owner = self()

    Req.Test.stub(Delivest.S3Stub, fn conn ->
      path = conn.request_path

      case conn.method do
        "GET" ->
          case Agent.get(store, &Map.fetch(&1, path)) do
            {:ok, body} -> Plug.Conn.send_resp(conn, 200, body)
            :error -> Plug.Conn.send_resp(conn, 404, "missing")
          end

        "PUT" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          Agent.update(store, &Map.put(&1, path, body))
          send(owner, {:uploaded, path})
          Plug.Conn.send_resp(conn, 200, "")

        "DELETE" ->
          Agent.update(store, &Map.delete(&1, path))
          Plug.Conn.send_resp(conn, 204, "")
      end
    end)

    store
  end

  defp use_bucket!(bucket) do
    initial = Application.fetch_env!(:delivest, Delivest.Media)

    Application.put_env(
      :delivest,
      Delivest.Media,
      Keyword.put(initial, :public_bucket, bucket)
    )

    on_exit(fn -> Application.put_env(:delivest, Delivest.Media, initial) end)
  end

  defp clear_franchise! do
    Repo.delete_all(EntityRelation)
    Repo.delete_all(ProductModifierGroup)
    Repo.delete_all(Delivest.Net.Modifier)
    Repo.delete_all(Delivest.Net.ModifierGroup)
    Repo.delete_all(Product)
    Repo.delete_all(Category)
    Repo.delete_all(Delivest.Media.File)
    Repo.delete_all(Delivest.Net.ProductTag)
    Repo.delete_all(Delivest.Delivery.Zone)
    Repo.delete_all(BranchInfo)
    Repo.delete_all(Branch)
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
