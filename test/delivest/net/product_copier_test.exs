defmodule Delivest.Net.ProductCopierTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.{Net, Relations}
  alias Delivest.Net.Product

  setup do
    from = insert(:branch)
    to = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    %{from: from, to: to, staff: staff}
  end

  defp branch_products(branch_id) do
    ids = Relations.list_target_ids("Branch", branch_id, "Product")
    Repo.all(from(p in Product, where: p.id in ^ids, preload: :category, order_by: p.name))
  end

  test "copies all products with photo and category but without crm id", ctx do
    {:ok, category} = Net.create_category(ctx.staff, ctx.from.id, %{"name" => "Soups"})
    media_id = Ecto.UUID.generate()

    insert_branch_product(ctx.from.id,
      name: "Borsch",
      price: 300,
      external_id: "fp-1",
      media_id: media_id,
      category_id: category.id
    )

    insert_branch_product(ctx.from.id, name: "Tea", price: 50)

    assert {:ok, 2} = Net.copy_products(ctx.staff, :all, ctx.from.id, ctx.to.id)

    assert [borsch, tea] = branch_products(ctx.to.id)
    assert %{name: "Borsch", price: 300, external_id: nil, media_id: ^media_id} = borsch
    assert borsch.category.name == "Soups"
    assert borsch.category.id != category.id
    assert tea.category == nil
  end

  test "copies only the chosen products", ctx do
    chosen = insert_branch_product(ctx.from.id, name: "Chosen")
    insert_branch_product(ctx.from.id, name: "Skipped")

    assert {:ok, 1} = Net.copy_products(ctx.staff, [chosen.id], ctx.from.id, ctx.to.id)
    assert [%{name: "Chosen"}] = branch_products(ctx.to.id)
  end

  test "ignores products of other branches", ctx do
    foreign = insert_branch_product(insert(:branch).id, name: "Foreign")

    assert {:ok, 0} = Net.copy_products(ctx.staff, [foreign.id], ctx.from.id, ctx.to.id)
  end

  test "requires permission and different branches", ctx do
    reader = insert(:staff, role: insert(:role, permissions: ["products.read"]))

    assert {:error, :forbidden} = Net.copy_products(reader, :all, ctx.from.id, ctx.to.id)
    assert {:error, :same_branch} = Net.copy_products(ctx.staff, :all, ctx.from.id, ctx.from.id)
  end
end
