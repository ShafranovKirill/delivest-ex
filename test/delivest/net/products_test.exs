defmodule Delivest.Net.ProductsTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Net
  alias Delivest.Net.Catalogs
  alias Delivest.Net.Product
  alias Delivest.Identity.Branch
  alias Delivest.Relations

  defp staff_with_permissions(permissions) do
    role = insert(:role, permissions: permissions)
    insert(:staff, role: role)
  end

  defp grant_product_branch(staff, product) do
    branch = insert(:branch)
    Relations.create_relation(Delivest.Repo, "Branch", branch.id, "Product", product.id, %{})
    insert(:staff_branch, staff: staff, branch: branch)
  end

  defp insert_product(attrs \\ %{}) do
    attrs = Map.merge(%{name: "Product", price: 100, is_active: true}, attrs)

    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert!()
  end

  describe "list_staff_products_for_branch/4" do
    test "returns non-deleted products linked to the branch" do
      staff = staff_with_permissions(["products.read"])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)
      visible = insert_product(%{name: "Visible"})
      inactive = insert_product(%{name: "Inactive", is_active: false})
      deleted = insert_product(%{name: "Deleted", deleted_at: DateTime.utc_now(:second)})
      unrelated = insert_product(%{name: "Unrelated"})

      for product <- [visible, inactive, deleted] do
        assert {:ok, _} =
                 Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)
      end

      assert {:ok, {products, _meta}} = Net.list_staff_products_for_branch(staff, branch.id)
      product_ids = Enum.map(products, & &1.id)
      assert Enum.sort(product_ids) == Enum.sort([visible.id, inactive.id])
      refute deleted.id in product_ids
      refute unrelated.id in product_ids
    end

    test "returns forbidden without products.read permission" do
      staff = staff_with_permissions([])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)

      assert {:error, :forbidden} = Net.list_staff_products_for_branch(staff, branch.id)
    end

    test "pages every branch product once when sort values are equal" do
      staff = staff_with_permissions(["products.read"])
      branch = insert(:branch)
      other_branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)
      timestamp = ~U[2025-01-01 00:00:00Z]

      products =
        for n <- 1..11 do
          product = insert_product(%{name: "Product #{n}", price: 100})
          product = Repo.update!(Ecto.Changeset.change(product, inserted_at: timestamp))
          Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)
          product
        end

      outside = insert_product(%{name: "Outside", price: 100})
      Relations.create_relation(Repo, "Branch", other_branch.id, "Product", outside.id)

      for order_by <- [nil, ["price"]] do
        pages =
          for page <- 1..2 do
            params = %{"page" => page, "page_size" => 10}
            params = if order_by, do: Map.put(params, "order_by", order_by), else: params

            assert {:ok, {rows, meta}} =
                     Net.list_staff_products_for_branch(staff, branch.id, params)

            assert meta.total_count == 11
            rows
          end

        ids = pages |> List.flatten() |> Enum.map(& &1.id)
        assert ids == Enum.sort(Enum.map(products, & &1.id))
        refute outside.id in ids
        assert Enum.map(pages, &length/1) == [10, 1]
      end
    end

    test "accepts atom params, fills missing directions, and rejects invalid sort" do
      staff = staff_with_permissions(["products.read"])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)
      first = insert_product(%{name: "First", price: 100})
      second = insert_product(%{name: "Second", price: 200})

      for product <- [first, second] do
        Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)
      end

      assert {:ok, {rows, _meta}} =
               Net.list_staff_products_for_branch(staff, branch.id, %{
                 order_by: [:price, :name],
                 order_directions: [:desc],
                 page: 1,
                 page_size: 1
               })

      assert Enum.map(rows, & &1.id) == [second.id]

      assert {:error, %Flop.Meta{}} =
               Net.list_staff_products_for_branch(staff, branch.id, %{order_by: ["unknown"]})
    end

    test "reports empty, single, and full first pages" do
      staff = staff_with_permissions(["products.read"])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)

      for count <- [0, 1, 10] do
        additional = count - if(count == 10, do: 1, else: 0)

        for {_, n} <- List.duplicate(nil, additional) |> Enum.with_index() do
          product = insert_product(%{name: "Product #{count}-#{n}"})
          Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)
        end

        assert {:ok, {rows, meta}} =
                 Net.list_staff_products_for_branch(staff, branch.id, %{
                   "page" => 1,
                   "page_size" => 10
                 })

        assert length(rows) == count
        assert meta.total_count == count
      end
    end
  end

  describe "create_product/3" do
    test "creates a product and links it to the branch" do
      staff = staff_with_permissions(["products.create"])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)

      assert {:ok, %Product{} = product} =
               Net.create_product(staff, branch.id, %{"name" => "New", "price" => 250})

      assert product.name == "New"
      assert product.price == 250
      assert product.id in Relations.list_target_ids("Branch", branch.id, "Product")
    end

    test "returns validation errors for a negative price" do
      staff = staff_with_permissions(["products.create"])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)

      assert {:error, changeset} =
               Net.create_product(staff, branch.id, %{"name" => "Bad", "price" => -1})

      assert "must be greater than or equal to 0" in errors_on(changeset).price
    end

    test "returns forbidden without products.create permission" do
      staff = staff_with_permissions([])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)

      assert {:error, :forbidden} =
               Net.create_product(staff, branch.id, %{"name" => "New", "price" => 100})
    end
  end

  describe "update_product/3" do
    test "updates a product when permitted" do
      staff = staff_with_permissions(["products.update"])
      product = insert_product(%{name: "Old"})
      grant_product_branch(staff, product)

      assert {:ok, updated} =
               Net.update_product(staff, product, %{"name" => "Updated", "price" => 125})

      assert updated.name == "Updated"
      assert updated.price == 125
    end

    test "an editor of another branch cannot change the product" do
      staff = staff_with_permissions(["products.update", "products.delete"])
      product = insert_product()
      grant_product_branch(staff_with_permissions([]), product)
      insert(:staff_branch, staff: staff, branch: insert(:branch))

      assert {:error, :forbidden} = Net.update_product(staff, product, %{"name" => "X"})
      assert {:error, :forbidden} = Net.soft_delete_product(staff, product)
    end

    test "an editor of one owner branch cannot update or delete a shared product" do
      staff = staff_with_permissions(["products.update", "products.delete"])
      product = insert_product()
      grant_product_branch(staff, product)
      grant_product_branch(staff_with_permissions([]), product)

      assert {:error, :forbidden} = Net.update_product(staff, product, %{"name" => "X"})
      assert {:error, :forbidden} = Net.soft_delete_product(staff, product)
      assert Repo.get!(Product, product.id).name == product.name
    end

    test "shared product update invalidates and broadcasts to both owner branches" do
      staff = staff_with_permissions(["products.update"])
      category = insert(:category, is_active: true)
      product = insert_product(%{name: "Old", price: 100, category_id: category.id})
      branches = for _ <- 1..2, do: grant_product_branch(staff, product).branch
      Enum.each(branches, &Delivest.Net.Products.subscribe_branch(&1.id))
      versions = Map.new(branches, &{&1.id, Repo.get!(Branch, &1.id).catalog_version})

      Enum.each(branches, fn branch ->
        Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id)

        assert {:ok, [%{products: [%{id: id, name: "Old", price: 100}]}]} =
                 Catalogs.get_menu_for_branch(branch.id)

        assert id == product.id
      end)

      assert {:ok, updated} =
               Net.update_product(staff, product, %{"name" => "New", "price" => 125})

      assert updated.name == "New"
      assert_receive {:product_updated, %Product{id: id1}}
      assert_receive {:product_updated, %Product{id: id2}}
      assert id1 == product.id and id2 == product.id

      Enum.each(branches, fn branch ->
        assert Repo.get!(Branch, branch.id).catalog_version > versions[branch.id]

        assert {:ok, [%{products: [%{id: id, name: "New", price: 125}]}]} =
                 Catalogs.get_menu_for_branch(branch.id)

        assert id == product.id
      end)
    end

    test "returns forbidden without products.update permission" do
      staff = staff_with_permissions([])
      product = insert_product()

      assert {:error, :forbidden} =
               Net.update_product(staff, product, %{"name" => "Updated"})
    end
  end

  describe "soft_delete_product/2" do
    test "sets deleted_at when permitted" do
      staff = staff_with_permissions(["products.delete"])
      product = insert_product()
      grant_product_branch(staff, product)

      assert {:ok, deleted} = Net.soft_delete_product(staff, product)
      assert %DateTime{} = deleted.deleted_at
    end

    test "returns forbidden without products.delete permission" do
      staff = staff_with_permissions([])
      product = insert_product()

      assert {:error, :forbidden} = Net.soft_delete_product(staff, product)
    end
  end

  describe "soft_delete_products/3" do
    test "deletes only selected products of the branch" do
      staff = staff_with_permissions(["products.delete"])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)
      selected = insert_product(%{name: "Selected"})
      kept = insert_product(%{name: "Kept"})
      foreign = insert_product(%{name: "Foreign"})

      for product <- [selected, kept] do
        assert {:ok, _} =
                 Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)
      end

      assert {:ok, [deleted]} =
               Net.soft_delete_products(staff, branch.id, [selected.id, foreign.id])

      assert deleted.id == selected.id
      assert %DateTime{} = Repo.get!(Product, selected.id).deleted_at
      assert is_nil(Repo.get!(Product, kept.id).deleted_at)
      assert is_nil(Repo.get!(Product, foreign.id).deleted_at)
    end

    test "returns forbidden without products.delete permission" do
      staff = staff_with_permissions([])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)
      product = insert_product()

      assert {:error, :forbidden} = Net.soft_delete_products(staff, branch.id, [product.id])
    end
  end

  describe "product order" do
    defp branch_product(branch, attrs) do
      product = insert(:product, attrs)

      assert {:ok, _} =
               Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)

      product
    end

    test "new products go to the end of their category" do
      staff = staff_with_permissions(["products.create"])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)
      category = insert(:category)

      assert {:ok, first} =
               Net.create_product(staff, branch.id, %{
                 "name" => "B",
                 "price" => 1,
                 "category_id" => category.id
               })

      assert {:ok, second} =
               Net.create_product(staff, branch.id, %{
                 "name" => "A",
                 "price" => 1,
                 "category_id" => category.id
               })

      assert second.order > first.order

      assert Enum.map(Net.list_category_products(branch.id, category.id), & &1.id) ==
               [first.id, second.id]
    end

    test "moving to another category puts the product at its end" do
      staff = staff_with_permissions(["products.update"])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)
      from = insert(:category)
      to = insert(:category)
      product = branch_product(branch, %{name: "Moved", category_id: from.id, order: 1.0})
      branch_product(branch, %{name: "There", category_id: to.id, order: 5.0})

      assert {:ok, moved} = Net.update_product(staff, product, %{"category_id" => to.id})
      assert moved.order == 6.0
    end

    test "update_product_order places the product between its neighbours" do
      staff = staff_with_permissions(["products.update"])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)
      category = insert(:category)
      a = branch_product(branch, %{name: "A", category_id: category.id, order: 1.0})
      b = branch_product(branch, %{name: "B", category_id: category.id, order: 2.0})
      c = branch_product(branch, %{name: "C", category_id: category.id, order: 3.0})

      assert {:ok, _} = Net.update_product_order(staff, c, a.order, b.order)

      assert Enum.map(Net.list_category_products(branch.id, category.id), & &1.id) ==
               [a.id, c.id, b.id]
    end

    test "update_product_order requires products.update" do
      staff = staff_with_permissions([])
      product = insert_product()

      assert {:error, :forbidden} = Net.update_product_order(staff, product, nil, nil)
    end
  end

  describe "crm ids" do
    alias Delivest.Net.ProductCrmIds

    setup do
      staff = staff_with_permissions(["products.create", "products.update"])
      branch = insert(:branch)
      insert(:staff_branch, staff: staff, branch: branch)
      %{staff: staff, branch: branch}
    end

    defp crm_ids(product, branch_id),
      do: product.id |> List.wrap() |> ProductCrmIds.by_product(:frontpad, branch_id)

    test "are stored per provider and updated in place", %{staff: staff, branch: branch} do
      {:ok, product} =
        Net.create_product(staff, branch.id, %{
          "name" => "Soup",
          "price" => 100,
          "crm_ids" => %{"frontpad" => " 101 "}
        })

      assert crm_ids(product, branch.id) == %{product.id => "101"}

      {:ok, product} = Net.update_product(staff, product, %{"crm_ids" => %{"frontpad" => "102"}})
      assert crm_ids(product, branch.id) == %{product.id => "102"}

      {:ok, product} = Net.update_product(staff, product, %{"name" => "Borsch"})
      assert crm_ids(product, branch.id) == %{product.id => "102"}

      {:ok, product} = Net.update_product(staff, product, %{"crm_ids" => %{"frontpad" => ""}})
      assert crm_ids(product, branch.id) == %{}
    end

    test "cannot repeat inside a branch but can across branches", %{staff: staff, branch: branch} do
      attrs = %{"name" => "Soup", "price" => 100, "crm_ids" => %{"frontpad" => "7"}}

      {:ok, _first} = Net.create_product(staff, branch.id, attrs)
      assert {:error, changeset} = Net.create_product(staff, branch.id, attrs)
      assert %{crm_ids: [_message]} = errors_on(changeset)

      other = insert(:branch)
      insert(:staff_branch, staff: staff, branch: other)
      assert {:ok, _other} = Net.create_product(staff, other.id, attrs)
    end

    test "shared product CRM IDs remain scoped to the explicit branch", %{
      staff: staff,
      branch: branch
    } do
      other = insert(:branch)
      insert(:staff_branch, staff: staff, branch: other)

      {:ok, product} =
        Net.create_product(staff, branch.id, %{
          "name" => "Shared",
          "price" => 100,
          "crm_ids" => %{"frontpad" => "A"}
        })

      Relations.create_relation(Repo, "Branch", other.id, "Product", product.id)

      assert {:error, :forbidden} =
               Net.update_product(staff, product, %{"crm_ids" => %{"frontpad" => "wrong"}})

      assert {:ok, _} =
               Net.update_product(staff, product, %{
                 "branch_id" => other.id,
                 "crm_ids" => %{"frontpad" => "B"}
               })

      assert ProductCrmIds.by_product([product.id], :frontpad, branch.id) == %{product.id => "A"}
      assert ProductCrmIds.by_product([product.id], :frontpad, other.id) == %{product.id => "B"}

      assert {:ok, _} =
               Net.update_product(staff, product, %{
                 "branch_id" => branch.id,
                 "crm_ids" => %{"frontpad" => "A2"}
               })

      assert ProductCrmIds.by_product([product.id], :frontpad, branch.id) == %{product.id => "A2"}
      assert ProductCrmIds.by_product([product.id], :frontpad, other.id) == %{product.id => "B"}
    end

    test "one branch editor may update only that branch's CRM ID", %{branch: a} do
      admin = staff_with_permissions(["admin"])
      b = insert(:branch)
      editor = staff_with_permissions(["products.update"])
      insert(:staff_branch, staff: editor, branch: b)

      {:ok, product} =
        Net.create_product(admin, a.id, %{
          "name" => "Shared",
          "price" => 100,
          "crm_ids" => %{"frontpad" => "A"}
        })

      Relations.create_relation(Repo, "Branch", b.id, "Product", product.id)

      assert {:ok, _} =
               Net.update_product(editor, product, %{
                 "branch_id" => b.id,
                 "crm_ids" => %{"frontpad" => "B"}
               })

      assert {:error, :forbidden} =
               Net.update_product(editor, product, %{
                 "branch_id" => b.id,
                 "crm_ids" => %{"frontpad" => "C"},
                 "name" => "Foreign edit"
               })

      assert Repo.reload!(product).name == "Shared"
      assert ProductCrmIds.by_product([product.id], :frontpad, a.id) == %{product.id => "A"}
      assert ProductCrmIds.by_product([product.id], :frontpad, b.id) == %{product.id => "B"}
    end
  end
end
