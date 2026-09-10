defmodule Delivest.Net.StocksTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.{Media, Net, Repo, Relations}
  alias Delivest.Media.File
  alias Delivest.Net.Stock

  defp staff_with_permissions(permissions) do
    role = insert(:role, permissions: permissions)
    insert(:staff, role: role)
  end

  defp create_media_file(owner_id, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          bucket: "stocks",
          key: "stocks/#{Ecto.UUID.generate()}.jpg",
          original_name: "stock.jpg",
          mime_type: "image/jpeg",
          size: 42,
          context: :stock,
          owner_id: owner_id
        },
        attrs
      )

    {:ok, %File{} = file} = Media.create_file(attrs)
    file
  end

  defp insert_stock(attrs) do
    media = create_media_file(insert(:staff).id)

    stock_attrs =
      Map.merge(
        %{
          "media_id" => media.id,
          "text" => "Stock",
          "is_active" => true,
          "order" => 1.0
        },
        attrs
      )

    %Stock{}
    |> Stock.changeset(stock_attrs)
    |> Repo.insert!()
  end

  describe "list_staff_stocks_for_branch/2" do
    test "returns active stocks ordered by order and includes inactive for authorized staff" do
      staff = staff_with_permissions(["stocks.read"])
      branch = insert(:branch)

      first_media = create_media_file(staff.id)
      second_media = create_media_file(staff.id)
      inactive_media = create_media_file(staff.id)

      first_stock =
        insert_stock(%{"media_id" => first_media.id, "text" => "First", "order" => 2.0})

      second_stock =
        insert_stock(%{"media_id" => second_media.id, "text" => "Second", "order" => 1.0})

      inactive_stock =
        insert_stock(%{
          "media_id" => inactive_media.id,
          "text" => "Inactive",
          "order" => 3.0,
          "is_active" => false
        })

      for stock <- [first_stock, second_stock, inactive_stock] do
        assert {:ok, _relation} =
                 Relations.create_relation(Repo, "Branch", branch.id, "Stock", stock.id, %{})
      end

      result = Net.list_staff_stocks_for_branch(staff, branch.id)
      assert Enum.map(result, & &1.id) == [second_stock.id, first_stock.id, inactive_stock.id]
    end

    test "returns {:error, :forbidden} when staff lacks read permission" do
      staff = staff_with_permissions(["other.permission"])
      branch = insert(:branch)

      assert {:error, :forbidden} = Net.list_staff_stocks_for_branch(staff, branch.id)
    end
  end

  describe "list_stocks_for_branch/1" do
    test "returns only active stocks ordered by order and caches them" do
      branch = insert(:branch)
      staff = staff_with_permissions(["stocks.read"])

      media1 = create_media_file(staff.id)
      media2 = create_media_file(staff.id)
      media3 = create_media_file(staff.id)

      first = insert_stock(%{"media_id" => media1.id, "text" => "Visible 1", "order" => 2.0})
      second = insert_stock(%{"media_id" => media2.id, "text" => "Visible 2", "order" => 1.0})

      inactive =
        insert_stock(%{
          "media_id" => media3.id,
          "text" => "Hidden",
          "order" => 0.5,
          "is_active" => false
        })

      for stock <- [first, second, inactive] do
        assert {:ok, _relation} =
                 Relations.create_relation(Repo, "Branch", branch.id, "Stock", stock.id, %{})
      end

      assert [%Stock{}, %Stock{}] = result = Net.list_stocks_for_branch(branch.id)
      assert Enum.map(result, & &1.id) == [second.id, first.id]

      assert {:ok, cached} = Cachex.get(:stock_cache, branch.id)
      assert Enum.map(cached, & &1.id) == [second.id, first.id]
    end
  end

  describe "create_stock/3" do
    test "creates stock, assigns next order and links it to branch" do
      staff = staff_with_permissions(["stocks.create"])
      branch = insert(:branch)
      media = create_media_file(staff.id)

      assert {:ok, %Stock{} = stock} =
               Net.create_stock(staff, branch.id, %{"media_id" => media.id, "text" => "New"})

      assert stock.text == "New"
      assert stock.order == 1.0
      assert stock.id in Relations.list_target_ids("Branch", branch.id, "Stock")
    end

    test "returns {:error, :forbidden} without permission" do
      staff = staff_with_permissions([])
      branch = insert(:branch)
      media = create_media_file(insert(:staff).id)

      assert {:error, :forbidden} =
               Net.create_stock(staff, branch.id, %{"media_id" => media.id, "text" => "Nope"})
    end

    test "returns validation errors when media_id is missing" do
      staff = staff_with_permissions(["stocks.create"])
      branch = insert(:branch)

      assert {:error, changeset} =
               Net.create_stock(staff, branch.id, %{"text" => "Missing media"})

      assert "can't be blank" in errors_on(changeset).media_id
    end
  end

  describe "update_stock/3" do
    test "updates stock when permitted" do
      staff = staff_with_permissions(["stocks.update"])
      stock = insert_stock(%{"text" => "Old"})
      branch = insert(:branch)

      assert {:ok, _relation} =
               Relations.create_relation(Repo, "Branch", branch.id, "Stock", stock.id, %{})

      assert {:ok, %Stock{} = updated} =
               Net.update_stock(staff, stock, %{"text" => "Updated"})

      assert updated.text == "Updated"
    end

    test "returns {:error, :forbidden} without permission" do
      staff = staff_with_permissions([])
      stock = insert_stock(%{"text" => "Old"})

      assert {:error, :forbidden} = Net.update_stock(staff, stock, %{"text" => "Updated"})
    end
  end

  describe "update_stock_order/4" do
    test "calculates order based on neighbors" do
      staff = staff_with_permissions(["stocks.update"])
      stock = insert_stock(%{"order" => 2.0})
      branch = insert(:branch)

      assert {:ok, _relation} =
               Relations.create_relation(Repo, "Branch", branch.id, "Stock", stock.id, %{})

      assert {:ok, %Stock{} = updated} = Net.update_stock_order(staff, stock, 1.0, 3.0)
      assert updated.order == 2.0
    end

    test "returns {:error, :forbidden} without permission" do
      staff = staff_with_permissions([])
      stock = insert_stock(%{"order" => 2.0})

      assert {:error, :forbidden} = Net.update_stock_order(staff, stock, 1.0, 3.0)
    end
  end

  describe "delete_stock/2" do
    test "deletes stock when permitted" do
      staff = staff_with_permissions(["stocks.delete"])
      stock = insert_stock(%{"text" => "Delete me"})
      branch = insert(:branch)

      assert {:ok, _relation} =
               Relations.create_relation(Repo, "Branch", branch.id, "Stock", stock.id, %{})

      assert {:ok, %Stock{} = deleted} = Net.delete_stock(staff, stock)
      assert deleted.id == stock.id
      assert Repo.get(Stock, stock.id) == nil
    end

    test "returns {:error, :forbidden} without permission" do
      staff = staff_with_permissions([])
      stock = insert_stock(%{"text" => "Delete me"})

      assert {:error, :forbidden} = Net.delete_stock(staff, stock)
    end
  end
end
