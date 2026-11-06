defmodule Delivest.SiteSnapshotTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory

  alias Delivest.{Relations, Repo, SiteSnapshot}
  alias Delivest.Net.{Product, Modifier, ModifierGroup, ProductModifierGroup}
  alias Delivest.Media.File, as: MediaFile
  alias Delivest.Franchise.Settings, as: FranchiseSettings
  alias Delivest.Relations.EntityRelation

  test "exports a branch and imports its catalog idempotently" do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    source = insert(:branch, name: "Source")
    target = insert(:branch, name: "Target")
    category = insert(:category, name: "Pizza")
    product = insert(:product, name: "Margherita", category_id: category.id, price: 50_000)

    assert {:ok, _} =
             Relations.create_relation(Repo, "Branch", source.id, "Category", category.id)

    assert {:ok, _} = Relations.create_relation(Repo, "Branch", source.id, "Product", product.id)
    assert {:ok, archive} = SiteSnapshot.export(staff, source.id)

    Repo.delete_all(from r in EntityRelation, where: r.from_id == ^source.id)
    Repo.delete!(product)
    Repo.delete!(category)
    Repo.delete!(source)

    assert {:ok, %{products: 1, categories: 1}} = SiteSnapshot.import(staff, target.id, archive)
    assert Repo.get!(Product, product.id).price == 50_000
    assert Relations.related?("Branch", target.id, "Category", category.id)
    assert {:ok, %{products: 1}} = SiteSnapshot.import(staff, target.id, archive)
    assert Repo.aggregate(Product, :count) == 1
  end

  test "branch editor cannot import installation-global modifier entries" do
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    source = insert(:branch)
    target = insert(:branch)
    product = insert_branch_product(source.id)
    group = Repo.insert!(%ModifierGroup{name: "Shared", min: 0, max: 1})
    Repo.insert!(%ProductModifierGroup{product_id: product.id, group_id: group.id, position: 0})
    assert {:ok, archive} = SiteSnapshot.export(admin, source.id)

    permissions =
      ~w(branches.read branches.update categories.read categories.create categories.update products.read products.create products.update delivery.read delivery.update franchise.update)

    editor = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: editor, branch: target)

    assert {:error, :forbidden} = SiteSnapshot.import(editor, target.id, archive)
    assert Repo.get!(ModifierGroup, group.id).name == "Shared"
  end

  test "copies product, modifier and brand images into the destination bucket" do
    owner = self()
    initial = Application.fetch_env!(:delivest, Delivest.Media)
    on_exit(fn -> Application.put_env(:delivest, Delivest.Media, initial) end)
    store = start_supervised!({Agent, fn -> %{} end})

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

    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    source = insert(:branch, name: "Source")
    target = insert(:branch, name: "Target")
    product = insert(:product)

    photo = Delivest.S3Stub.png(2, 2)

    media =
      Repo.insert!(%MediaFile{
        bucket: "delivest",
        key: "products/photo.png",
        original_name: "photo.png",
        mime_type: "image/png",
        size: byte_size(photo),
        context: :product,
        owner_id: product.id
      })

    product |> Ecto.Changeset.change(media_id: media.id) |> Repo.update!()
    group = Repo.insert!(%ModifierGroup{name: "Extras", min: 0, max: 1})

    modifier =
      Repo.insert!(%Modifier{
        group_id: group.id,
        name: "Cheese",
        price: 100,
        photo_key: "modifiers/photo.png"
      })

    Repo.insert!(%ProductModifierGroup{product_id: product.id, group_id: group.id})

    franchise =
      Repo.one(FranchiseSettings) || Repo.insert!(%FranchiseSettings{name: "Source brand"})

    franchise |> Ecto.Changeset.change(logo_key: "franchise/logo/main.png") |> Repo.update!()
    assert {:ok, _} = Relations.create_relation(Repo, "Branch", source.id, "Product", product.id)

    Agent.update(store, fn files ->
      files
      |> Map.put("/delivest/products/photo.png", photo)
      |> Map.put("/delivest/modifiers/photo.png", Delivest.S3Stub.png(3, 3))
      |> Map.put("/delivest/franchise/logo/main.png", Delivest.S3Stub.png(4, 4))
    end)

    assert {:ok, archive} = SiteSnapshot.export(staff, source.id)
    Repo.delete_all(from r in EntityRelation, where: r.from_id == ^source.id)
    Repo.delete!(%ProductModifierGroup{product_id: product.id, group_id: group.id})
    Repo.delete!(modifier)
    Repo.delete!(group)
    Repo.delete!(product)
    Repo.delete!(media)
    Repo.delete!(source)

    Application.put_env(
      :delivest,
      Delivest.Media,
      Keyword.put(initial, :public_bucket, "target-bucket")
    )

    conflicting_branch = insert(:branch, name: "Source")
    assert {:error, %Ecto.Changeset{}} = SiteSnapshot.import(staff, target.id, archive)
    assert_received {:uploaded, "/target-bucket/site-snapshot/" <> _}
    assert Repo.reload!(target).name == "Target"
    assert Repo.aggregate(Product, :count) == 0

    refute Agent.get(
             store,
             &Enum.any?(Map.keys(&1), fn key -> String.starts_with?(key, "/target-bucket/") end)
           )

    Repo.delete!(conflicting_branch)

    assert {:ok, %{products: 1, media: 1}} = SiteSnapshot.import(staff, target.id, archive)
    assert_receive {:uploaded, "/target-bucket/site-snapshot/" <> _}
    assert String.starts_with?(Repo.get!(Modifier, modifier.id).photo_key, "site-snapshot/")
    assert String.starts_with?(Repo.one!(FranchiseSettings).logo_key, "site-snapshot/")
    assert Repo.get!(MediaFile, media.id).bucket == "target-bucket"
    assert {:ok, _} = SiteSnapshot.import(staff, target.id, archive)
  end

  test "maps a catalog UUID owned by another branch into the target" do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    source = insert(:branch, name: "Source")
    target = insert(:branch, name: "Target")
    category = insert(:category)

    assert {:ok, _} =
             Relations.create_relation(Repo, "Branch", source.id, "Category", category.id)

    assert {:ok, archive} = SiteSnapshot.export(staff, source.id)
    source |> Delivest.Identity.Branch.changeset(%{name: "Source after export"}) |> Repo.update!()

    assert {:ok, %{created: 1, updated: 0}} = SiteSnapshot.import(staff, target.id, archive)
    assert Repo.reload!(target).name == "Source"
    assert Relations.related?("Branch", source.id, "Category", category.id)
    refute Relations.related?("Branch", target.id, "Category", category.id)

    assert [target_category] =
             Repo.all(from c in Delivest.Net.Category, where: c.id != ^category.id)

    assert Relations.related?("Branch", target.id, "Category", target_category.id)
    assert {:ok, %{created: 0, updated: 1}} = SiteSnapshot.import(staff, target.id, archive)
  end

  test "rejects a snapshot from another build before changing the branch" do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    branch = insert(:branch)
    assert {:ok, archive} = SiteSnapshot.export(staff, branch.id)
    {:ok, files} = :zip.extract(archive, [:memory])

    files =
      Enum.map(files, fn
        {~c"manifest.json", body} ->
          changed = body |> Jason.decode!() |> Map.put("build", "different") |> Jason.encode!()
          {~c"manifest.json", changed}

        other ->
          other
      end)

    {:ok, {_, changed_archive}} =
      :zip.create(~c"changed.zip", files, [:memory, {:uncompress, :all}])

    assert {:error, :different_build} = SiteSnapshot.import(staff, branch.id, changed_archive)
    assert Repo.reload!(branch).name == branch.name
  end

  test "rejects a corrupt archive before any catalog change" do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    branch = insert(:branch)
    assert {:error, :invalid_archive} = SiteSnapshot.import(staff, branch.id, "broken")
    assert Repo.aggregate(Product, :count) == 0
  end

  test "rejects invalid product price before importing records" do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    source = insert(:branch)
    target = insert(:branch, name: "Target")
    product = insert(:product, price: 1000)
    assert {:ok, _} = Relations.create_relation(Repo, "Branch", source.id, "Product", product.id)
    assert {:ok, archive} = SiteSnapshot.export(staff, source.id)
    {:ok, files} = :zip.extract(archive, [:memory])

    data =
      files
      |> Enum.find_value(fn {path, body} -> if path == ~c"data.json", do: Jason.decode!(body) end)

    data = %{data | "products" => [Map.put(hd(data["products"]), "price", -1)]}
    body = Jason.encode!(data)

    files =
      Enum.map(files, fn
        {~c"data.json", _} ->
          {~c"data.json", body}

        {~c"manifest.json", manifest} ->
          value =
            manifest
            |> Jason.decode!()
            |> Map.put("data_size", byte_size(body))
            |> Map.put("data_sha256", :crypto.hash(:sha256, body) |> Base.encode16(case: :lower))

          {~c"manifest.json", Jason.encode!(value)}

        other ->
          other
      end)

    {:ok, {_, invalid}} = :zip.create(~c"invalid.zip", files, [:memory, {:uncompress, :all}])
    assert {:error, :invalid_archive} = SiteSnapshot.import(staff, target.id, invalid)
    assert Repo.reload!(target).name == "Target"
  end

  test "rejects forged nested settings before applying the branch" do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    source = insert(:branch, name: "Source")
    target = insert(:branch, name: "Target")
    assert {:ok, archive} = SiteSnapshot.export(staff, source.id)
    {:ok, files} = :zip.extract(archive, [:memory])

    data =
      files
      |> Enum.find_value(fn
        {~c"data.json", body} -> Jason.decode!(body)
        _ -> nil
      end)
      |> Map.put("info", %{"fulfillment" => %{"secret" => "forged"}})
      |> Jason.encode!()

    files =
      Enum.map(files, fn
        {~c"data.json", _} ->
          {~c"data.json", data}

        {~c"manifest.json", body} ->
          manifest =
            body
            |> Jason.decode!()
            |> Map.put("data_size", byte_size(data))
            |> Map.put("data_sha256", :crypto.hash(:sha256, data) |> Base.encode16(case: :lower))

          {~c"manifest.json", Jason.encode!(manifest)}

        other ->
          other
      end)

    {:ok, {_, forged_archive}} =
      :zip.create(~c"forged.zip", files, [:memory, {:uncompress, :all}])

    assert {:error, :invalid_archive} = SiteSnapshot.import(staff, target.id, forged_archive)
    assert Repo.reload!(target).name == "Target"
  end

  test "rejects a Unix symlink even when OTP lists the entry as a regular file" do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    branch = insert(:branch)
    assert {:ok, archive} = SiteSnapshot.export(staff, branch.id)
    end_offset = byte_size(archive) - 22

    <<0x06054B50::little-32, _::binary-size(12), directory_offset::little-32, 0::16>> =
      binary_part(archive, end_offset, 22)

    attributes_offset = directory_offset + 38
    <<prefix::binary-size(attributes_offset), _attributes::32, suffix::binary>> = archive
    archive = <<prefix::binary, 0xA1FF0000::little-32, suffix::binary>>

    assert {:error, :invalid_archive} = SiteSnapshot.import(staff, branch.id, archive)
  end
end
