defmodule Delivest.Net.ProductsTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Media
  alias Delivest.Net.Product
  alias Delivest.Net.Products
  alias Delivest.Relations

  defp staff_with_permissions(permissions) do
    role = insert(:role, permissions: permissions)
    insert(:staff, role: role)
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
      visible = insert_product(%{name: "Visible"})
      inactive = insert_product(%{name: "Inactive", is_active: false})
      deleted = insert_product(%{name: "Deleted", deleted_at: DateTime.utc_now(:second)})
      unrelated = insert_product(%{name: "Unrelated"})

      for product <- [visible, inactive, deleted] do
        assert {:ok, _} =
                 Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)
      end

      assert {:ok, {products, _meta}} = Products.list_staff_products_for_branch(staff, branch.id)
      product_ids = Enum.map(products, & &1.id)
      assert product_ids == [visible.id, inactive.id]
      refute deleted.id in product_ids
      refute unrelated.id in product_ids
    end

    test "returns forbidden without products.read permission" do
      staff = staff_with_permissions([])
      branch = insert(:branch)

      assert {:error, :forbidden} = Products.list_staff_products_for_branch(staff, branch.id)
    end
  end

  describe "create_product/3" do
    test "creates a product and links it to the branch" do
      staff = staff_with_permissions(["products.create"])
      branch = insert(:branch)

      assert {:ok, %Product{} = product} =
               Products.create_product(staff, branch.id, %{"name" => "New", "price" => 250})

      assert product.name == "New"
      assert product.price == 250
      assert product.id in Relations.list_target_ids("Branch", branch.id, "Product")
    end

    test "returns validation errors for a negative price" do
      staff = staff_with_permissions(["products.create"])
      branch = insert(:branch)

      assert {:error, changeset} =
               Products.create_product(staff, branch.id, %{"name" => "Bad", "price" => -1})

      assert "must be greater than or equal to 0" in errors_on(changeset).price
    end

    test "returns forbidden without products.create permission" do
      staff = staff_with_permissions([])
      branch = insert(:branch)

      assert {:error, :forbidden} =
               Products.create_product(staff, branch.id, %{"name" => "New", "price" => 100})
    end
  end

  describe "update_product/3" do
    test "updates a product when permitted" do
      staff = staff_with_permissions(["products.update"])
      product = insert_product(%{name: "Old"})

      assert {:ok, updated} =
               Products.update_product(staff, product, %{"name" => "Updated", "price" => 125})

      assert updated.name == "Updated"
      assert updated.price == 125
    end

    test "returns forbidden without products.update permission" do
      staff = staff_with_permissions([])
      product = insert_product()

      assert {:error, :forbidden} =
               Products.update_product(staff, product, %{"name" => "Updated"})
    end
  end

  describe "soft_delete_product/2" do
    test "sets deleted_at when permitted" do
      staff = staff_with_permissions(["products.delete"])
      product = insert_product()

      assert {:ok, deleted} = Products.soft_delete_product(staff, product)
      assert %DateTime{} = deleted.deleted_at
    end

    test "returns forbidden without products.delete permission" do
      staff = staff_with_permissions([])
      product = insert_product()

      assert {:error, :forbidden} = Products.soft_delete_product(staff, product)
    end
  end

  describe "create_product_media_file/3" do
    test "creates a media file when permitted" do
      staff = staff_with_permissions(["products.create"])
      meta = %{bucket: "test", key: "products/file.jpg"}
      entry = %{client_name: "file.jpg", client_type: "image/jpeg", client_size: 42}

      assert {:ok, file} = Products.create_product_media_file(staff, meta, entry)
      assert file.original_name == "file.jpg"
      assert file.context == :product
      assert Media.get_file(file.id).id == file.id
    end

    test "returns forbidden without product permissions" do
      staff = staff_with_permissions([])
      meta = %{bucket: "test", key: "products/file.jpg"}
      entry = %{client_name: "file.jpg", client_type: "image/jpeg", client_size: 42}

      assert {:error, :forbidden} = Products.create_product_media_file(staff, meta, entry)
    end
  end
end
