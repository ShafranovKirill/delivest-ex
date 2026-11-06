defmodule Delivest.Net.MenuImportTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Integrations.Iiko.Menu
  alias Delivest.Net.{MenuImport, Modifiers, Product}
  alias Delivest.{Relations, Repo}
  alias Delivest.Identity.Branch

  defp nomenclature(pizza_price) do
    %{
      "groups" => [
        %{"id" => "g-pizza", "name" => "Пицца"},
        %{"id" => "g-mods", "name" => "Добавки", "isGroupModifier" => true}
      ],
      "sizes" => [%{"id" => "s-30", "name" => "30 см"}, %{"id" => "s-40", "name" => "40 см"}],
      "products" => [
        %{
          "id" => "p-pizza",
          "name" => "Маргарита",
          "type" => "Dish",
          "parentGroup" => "g-pizza",
          "weight" => 0.45,
          "sizePrices" => [
            %{"sizeId" => "s-30", "price" => %{"currentPrice" => pizza_price}},
            %{"sizeId" => "s-40", "price" => %{"currentPrice" => pizza_price + 200}}
          ],
          "groupModifiers" => [
            %{
              "id" => "g-mods",
              "minAmount" => 0,
              "maxAmount" => 2,
              "childModifiers" => [%{"id" => "m-cheese"}]
            }
          ]
        },
        %{
          "id" => "m-cheese",
          "name" => "Сыр",
          "type" => "Modifier",
          "sizePrices" => [%{"price" => %{"currentPrice" => 60}}]
        },
        %{"id" => "g-mods", "name" => "Добавки", "type" => "Modifier"},
        %{
          "id" => "p-tea",
          "name" => "Чай",
          "type" => "Good",
          "sizePrices" => [%{"price" => %{"currentPrice" => 100}}]
        }
      ]
    }
  end

  test "the iiko menu is imported, updated and hides what disappeared" do
    branch = insert(:branch)
    staff = insert(:staff, role: build(:role, permissions: ["admin"]))
    menu = Menu.parse(nomenclature(500))

    assert %{added: [_, _], changed: [], hidden: []} = MenuImport.diff(branch.id, :iiko, menu)
    assert {:ok, %{added: 2}} = MenuImport.apply(staff, branch.id, :iiko, menu)

    pizza = Repo.get_by!(Product, name: "Маргарита")
    assert pizza.price == 50_000
    assert pizza.weight == 450
    assert pizza.category_id

    [size, mods] =
      Modifiers.for_products([pizza.id])[pizza.id] |> Enum.sort_by(& &1.is_size, :desc)

    assert size.is_size
    assert Enum.map(size.modifiers, & &1.price) |> Enum.sort() == [0, 20_000]
    assert [%{name: "Сыр", price: 6_000}] = mods.modifiers

    assert %{added: [], changed: [], hidden: []} = MenuImport.diff(branch.id, :iiko, menu)

    changed = Menu.parse(nomenclature(550))
    changed = %{changed | products: Enum.reject(changed.products, &(&1.name == "Чай"))}

    assert %{changed: [%{fields: [:price]}], hidden: [%Product{name: "Чай"}]} =
             MenuImport.diff(branch.id, :iiko, changed)

    assert {:ok, %{changed: 1, hidden: 1}} = MenuImport.apply(staff, branch.id, :iiko, changed)
    assert %Product{is_active: false} = Repo.get_by!(Product, name: "Чай")
    assert Repo.reload!(pizza).price == 55_000
  end

  test "products from a crm menu are owned by the crm" do
    alias Delivest.Identity.Branch.BranchInfo
    alias Delivest.Integrations.{Crm, Iiko}
    alias Delivest.Integrations.Crm.BranchSettings

    branch = insert(:branch)
    staff = insert(:staff, role: build(:role, permissions: ["admin"]))

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :iiko,
        menu_source: :crm,
        iiko: %Iiko.Settings{api_key: "k"}
      }
    })

    {:ok, _summary} = MenuImport.apply(staff, branch.id, :iiko, Menu.parse(nomenclature(500)))
    pizza = Repo.get_by!(Product, name: "Маргарита")

    assert Crm.menu_owner(branch.id, pizza.id) == "iiko"
    assert Crm.menu_owner(branch.id, insert(:product).id) == nil
  end

  test "create-only actor cannot import updates or hide products" do
    branch = insert(:branch)
    admin = insert(:staff, role: build(:role, permissions: ["admin"]))
    actor = insert(:staff, role: insert(:role, permissions: ["products.create"]))
    insert(:staff_branch, staff: actor, branch: branch)
    menu = Menu.parse(nomenclature(500))

    assert {:ok, _} = MenuImport.apply(admin, branch.id, :iiko, menu)
    pizza = Repo.get_by!(Product, name: "Маргарита")
    changed = Menu.parse(nomenclature(550))
    changed = %{changed | products: Enum.reject(changed.products, &(&1.name == "Чай"))}

    assert {:error, :forbidden} = MenuImport.apply(actor, branch.id, :iiko, changed)
    assert Repo.reload!(pizza).price == 50_000
    assert Repo.get_by!(Product, name: "Чай").is_active
  end

  test "shared import requires every owner and invalidates both branches" do
    a = insert(:branch)
    b = insert(:branch)
    admin = insert(:staff, role: build(:role, permissions: ["admin"]))
    initial = Menu.parse(nomenclature(500))
    assert {:ok, _} = MenuImport.apply(admin, a.id, :iiko, initial)
    pizza = Repo.get_by!(Product, name: "Маргарита")
    Relations.create_relation(Repo, "Branch", b.id, "Product", pizza.id)
    Relations.create_relation(Repo, "Branch", b.id, "Category", pizza.category_id)

    permissions =
      ~w(products.create products.update products.delete categories.create categories.update catalog.global.manage)

    editor = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: editor, branch: a)
    changed = Menu.parse(nomenclature(550))
    before_b = Repo.get!(Branch, b.id).catalog_version

    assert {:error, :forbidden} = MenuImport.apply(editor, a.id, :iiko, changed)
    assert Repo.reload!(pizza).price == 50_000
    assert Repo.get!(Branch, b.id).catalog_version == before_b

    assert {:ok, _} = MenuImport.apply(admin, a.id, :iiko, changed)
    assert Repo.reload!(pizza).price == 55_000
    assert Repo.get!(Branch, b.id).catalog_version > before_b
  end
end
