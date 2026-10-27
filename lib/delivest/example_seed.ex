defmodule Delivest.ExampleSeed do
  import Ecto.Query

  alias Delivest.{Media, Relations, Repo}
  alias Delivest.Franchise.Settings
  alias Delivest.Identity.Branch
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Media.File, as: MediaFile
  alias Delivest.Media.Thumbnails
  alias Delivest.Net.{Category, Product, Stock}

  @working_hours Map.new(
                   ~w(monday tuesday wednesday thursday friday saturday sunday),
                   &{&1, %{"open" => "10:00", "close" => "23:00", "enabled" => true}}
                 )

  def seed_branch do
    branch = Repo.preload(branch(), :info)

    if branch.info do
      info("Branch #{branch.name} already has its info")
    else
      %BranchInfo{}
      |> BranchInfo.changeset(%{
        branch_id: branch.id,
        address: "Москва, Тверская улица, 7",
        city: "Москва",
        latitude: 55.757718,
        longitude: 37.611347,
        phone_number: "+74951234567",
        delivery_time: 45,
        working_hours: @working_hours,
        ycart_settings: %{enabled: true}
      })
      |> Repo.insert!()

      info("Filled info of branch #{branch.name}")
    end

    if Repo.one(Settings) do
      info("Franchise settings already exist")
    else
      {:ok, _} =
        Delivest.Franchise.SettingsStore.save(%{
          name: "Delivest Pizza",
          description:
            "Готовим пиццу, комбо, завтраки и кофе из свежих продуктов и привозим горячими за 45 минут. Работаем каждый день с 10:00 до 23:00.",
          legal_form: "ООО",
          legal_name: "Деливест",
          inn: "7701234567",
          ogrn: "1027700123456",
          legal_address: "Москва, Тверская улица, 7",
          email: "hello@delivest.example",
          phone: "+74951234567"
        })

      info("Filled franchise settings")
    end
  end

  def seed_catalog do
    branch = branch()
    rows = read_json("catalog.json")

    rows
    |> Enum.chunk_by(& &1["category"])
    |> Enum.with_index(1)
    |> Enum.each(fn {[%{"category" => name} | _] = products, index} ->
      category = category(branch.id, name, index * 1.0)

      products
      |> Enum.with_index(1)
      |> Enum.each(fn {row, order} -> product(branch.id, category, row, order * 1.0) end)
    end)
  end

  def seed_stocks do
    branch = branch()
    existing = existing_stock_texts(branch.id)

    "stocks.json"
    |> read_json()
    |> Enum.reject(&(&1["text"] in existing))
    |> Enum.with_index(next_stock_order(branch.id))
    |> Enum.each(fn {row, order} -> stock(branch.id, row, order * 1.0) end)
  end

  defp branch do
    Branch
    |> where([b], is_nil(b.deleted_at))
    |> order_by([b], asc: b.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      %Branch{} = branch ->
        branch

      nil ->
        %Branch{}
        |> Branch.changeset(%{name: "Центральный филиал", slug: "central", is_active: true})
        |> Repo.insert!()
        |> tap(&info("Created branch #{&1.name}"))
    end
  end

  defp category(branch_id, name, order) do
    ids = Relations.list_target_ids("Branch", branch_id, "Category")

    case Repo.one(from c in Category, where: c.id in ^ids and c.name == ^name, limit: 1) do
      %Category{} = category ->
        category

      nil ->
        {:ok, category} =
          Repo.transaction(fn ->
            category =
              %Category{}
              |> Category.changeset(%{name: name, order: order, is_active: true})
              |> Repo.insert!()

            {:ok, _} =
              Relations.create_relation(Repo, "Branch", branch_id, "Category", category.id, %{})

            category
          end)

        info("Created category #{name}")
        category
    end
  end

  defp product(branch_id, category, row, order) do
    if Repo.exists?(from p in Product, where: p.external_id == ^row["external_id"]) do
      info("  #{row["name"]} already exists")
    else
      {:ok, product} =
        Repo.transaction(fn ->
          product =
            %Product{order: order}
            |> Product.changeset(%{
              name: row["name"],
              price: row["price"],
              weight: row["weight"],
              quantity: row["quantity"],
              description: row["description"],
              external_id: row["external_id"],
              category_id: category.id,
              slug: unique_slug(row["name"]),
              tags: tag_ids(row["tags"]),
              is_active: true
            })
            |> Repo.insert!()

          {:ok, _} =
            Relations.create_relation(Repo, "Branch", branch_id, "Product", product.id, %{})

          product
        end)

      media_id = upload(Path.join("catalog", row["name"] <> ".webp"), :product, product.id)
      if media_id, do: product |> Ecto.Changeset.change(media_id: media_id) |> Repo.update!()

      info("  Created #{product.name}#{if media_id, do: "", else: " without photo"}")
    end
  end

  defp stock(branch_id, row, order) do
    stock_id = Ecto.UUID.generate()
    media_id = upload(Path.join("stocks", row["photo"]), :stock, stock_id)

    product_id =
      Repo.one(
        from p in Product,
          where: p.name == ^row["product"] and is_nil(p.deleted_at),
          select: p.id,
          limit: 1
      )

    Repo.transaction(fn ->
      %Stock{id: stock_id}
      |> Stock.changeset(%{
        media_id: media_id,
        text: row["text"],
        product_id: product_id,
        order: order,
        is_active: true
      })
      |> Repo.insert!()

      {:ok, _} = Relations.create_relation(Repo, "Branch", branch_id, "Stock", stock_id, %{})
    end)

    info("Created promotion #{row["text"]}")
  end

  defp upload(relative_path, context, owner_id) do
    path = Path.join(images_dir(), relative_path)

    if File.exists?(path) do
      body = File.read!(path)
      mime = MIME.from_path(path)
      bucket = Media.public_bucket()
      key = "#{context}/#{owner_id}/#{Ecto.UUID.generate()}#{Path.extname(path)}"

      {:ok, _} = bucket |> ExAws.S3.put_object(key, body, content_type: mime) |> ExAws.request()

      file =
        %MediaFile{}
        |> MediaFile.changeset(%{
          bucket: bucket,
          key: key,
          original_name: Path.basename(path),
          mime_type: mime,
          size: byte_size(body),
          context: context,
          owner_id: owner_id,
          is_private: false
        })
        |> Repo.insert!()

      Thumbnails.store(file)
      file.id
    end
  end

  defp tag_ids(nil), do: []

  defp tag_ids(names) do
    Repo.all(from t in Delivest.Net.ProductTag, where: t.name in ^names, select: t.id)
  end

  defp unique_slug(name) do
    name
    |> Delivest.Slug.slugify()
    |> Kernel.||("product")
    |> Delivest.Slug.unique(&Repo.exists?(from p in Product, where: p.slug == ^&1))
  end

  defp existing_stock_texts(branch_id) do
    ids = Relations.list_target_ids("Branch", branch_id, "Stock")
    Repo.all(from s in Stock, where: s.id in ^ids, select: s.text)
  end

  defp next_stock_order(branch_id) do
    ids = Relations.list_target_ids("Branch", branch_id, "Stock")
    max = Repo.one(from s in Stock, where: s.id in ^ids, select: max(s.order))
    trunc(max || 0) + 1
  end

  defp read_json(name), do: images_dir() |> Path.join(name) |> File.read!() |> Jason.decode!()

  defp images_dir, do: Application.app_dir(:delivest, "priv/images")

  defp info(message), do: IO.puts(message)
end
