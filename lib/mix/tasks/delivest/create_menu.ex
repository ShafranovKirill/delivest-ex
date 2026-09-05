defmodule Mix.Tasks.Delivest.CreateMenu do
  use Mix.Task

  alias Delivest.Repo
  alias Delivest.Identity.Branch
  alias Delivest.Net.{Category, Product}
  alias Delivest.Relations
  alias Ecto.Multi

  @shortdoc "Seeds a branch with 6 categories and 3 products in each category"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    branch = get_or_create_branch()

    categories_data = [
      {"Пицца", "Горячая свежая пицца на пышном и тонком тесте",
       [
         {"Пепперони", "Классическая пицца с колбасками пепперони и моцареллой", 599},
         {"Маргарита", "Томатный соус, сыр моцарелла и свежий базилик", 449},
         {"Четыре сыра", "Моцарелла, пармезан, горгонзола и чеддер", 699}
       ]},
      {"Бургеры", "Сочные бургеры с мраморной говядиной",
       [
         {"Чизбургер", "Котлета из говядины, сыр чеддер, маринованные огурцы", 399},
         {"Двойной Бекон", "Две котлеты, двойной сыр, хрустящий бекон и соус BBQ", 549},
         {"Грибной Бургер", "Говяжья котлета, соус из шампиньонов и сыр эмменталь", 479}
       ]},
      {"Суши и Роллы", "Свежие роллы с лососем, тунцом и снежным крабом",
       [
         {"Филадельфия", "Лосось, сливочный сыр, огурец", 499},
         {"Калифорния", "Снежный краб, авокадо, икра тобико", 429},
         {"Запеченный с лососем", "Запеченный ролл со спайси соусом и лососем", 459}
       ]},
      {"Напитки", "Освежающие лимонады, соки и газировка",
       [
         {"Кола 0.5л", "Классический освежающий газированный напиток", 120},
         {"Домашний Лимонад 0.4л", "Натуральный лимонад с цитрусами и мятой", 180},
         {"Ягодный Морс 0.5л", "Морс из клюквы и брусники собственного приготовления", 150}
       ]},
      {"Закуски", "Хрустящие закуски для всей компании",
       [
         {"Картофель Фри", "Хрустящие ломтики золотистого картофеля", 190},
         {"Куриные Наггетсы", "Сочное куриное филе в панировке (6 шт)", 240},
         {"Сырные Палочки", "Обжаренные палочки из моцареллы с соусом", 290}
       ]},
      {"Десерты", "Сладкие десерты и выпечка",
       [
         {"Чизкейк Нью-Йорк", "Классический творожный чизкейк", 280},
         {"Шоколадный Фондан", "Теплый кекс с жидкой шоколадной начинкой", 320},
         {"Тирамису", "Итальянский десерт с кофейной пропиткой", 310}
       ]}
    ]

    Enum.each(Enum.with_index(categories_data, 1), fn {{cat_name, _cat_desc, products}, index} ->
      category = get_or_create_category(branch.id, cat_name, index * 1.0)

      Enum.each(products, fn {prod_name, prod_desc, price} ->
        get_or_create_product(branch.id, category.id, prod_name, prod_desc, price)
      end)
    end)

    Mix.shell().info("Catalog seeding finished successfully!")
  end

  defp get_or_create_branch do
    branch_name = "Центральный филиал"

    case Repo.get_by(Branch, name: branch_name) do
      %Branch{} = branch ->
        Mix.shell().info("Branch '#{branch_name}' already exists (ID: #{branch.id})")
        branch

      nil ->
        branch_params = %{
          name: branch_name,
          slug: "centralny-filial",
          is_active: true
        }

        changeset = Branch.changeset(%Branch{}, branch_params)

        case Repo.insert(changeset) do
          {:ok, branch} ->
            Mix.shell().info("Created branch: #{branch.name} (ID: #{branch.id})")
            branch

          {:error, changeset} ->
            Mix.shell().error("Failed to create branch:")
            IO.inspect(changeset.errors)
            raise "Cannot proceed without branch"
        end
    end
  end

  defp get_or_create_category(branch_id, name, order) do
    case Repo.get_by(Category, name: name) do
      %Category{} = category ->
        Mix.shell().info("  Category '#{name}' already exists")
        category

      nil ->
        category_params = %{
          name: name,
          order: order,
          is_active: true
        }

        Multi.new()
        |> Multi.insert(:category, Category.changeset(%Category{}, category_params))
        |> Multi.run(:relation, fn repo, %{category: category} ->
          Relations.create_relation(repo, "Branch", branch_id, "Category", category.id, %{})
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{category: category}} ->
            Mix.shell().info("  Created category: #{category.name} (ID: #{category.id})")
            category

          {:error, _failed_op, error, _changes} ->
            Mix.shell().error("Failed to create category '#{name}':")
            IO.inspect(error)
            raise "Cannot proceed without category"
        end
    end
  end

  defp get_or_create_product(branch_id, category_id, name, description, price) do
    case Repo.get_by(Product, category_id: category_id, name: name) do
      %Product{} = product ->
        Mix.shell().info("    Product '#{name}' already exists")
        product

      nil ->
        product_params = %{
          name: name,
          description: description,
          price: price,
          category_id: category_id,
          is_active: true,
          quantity: 10,
          weight: 350
        }

        Multi.new()
        |> Multi.insert(:product, Product.changeset(%Product{}, product_params))
        |> Multi.run(:relation_branch, fn repo, %{product: product} ->
          Relations.create_relation(repo, "Branch", branch_id, "Product", product.id, %{})
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{product: product}} ->
            Mix.shell().info("    Created product: #{product.name} (#{product.price} ₽)")
            product

          {:error, _failed_op, error, _changes} ->
            Mix.shell().error("Failed to create product '#{name}':")
            IO.inspect(error)
            raise "Cannot proceed without product"
        end
    end
  end
end
