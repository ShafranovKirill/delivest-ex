defmodule Delivest.Net.ProductSlugTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Net

  setup do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    %{staff: staff, branch: insert(:branch)}
  end

  test "slug is generated from the Russian name and kept unique", %{staff: staff, branch: branch} do
    {:ok, first} = Net.create_product(staff, branch.id, %{"name" => "Хинкали", "price" => 100})
    {:ok, second} = Net.create_product(staff, branch.id, %{"name" => "Хинкали", "price" => 120})

    assert first.slug == "hinkali"
    assert second.slug == "hinkali-2"
  end

  test "typed slug is normalized and kept on rename", %{staff: staff, branch: branch} do
    {:ok, product} =
      Net.create_product(staff, branch.id, %{
        "name" => "Плов",
        "price" => 300,
        "slug" => "Плов Узбекский"
      })

    assert product.slug == "plov-uzbekskiy"

    {:ok, renamed} = Net.update_product(staff, product, %{"name" => "Плов по-фергански"})
    assert renamed.slug == "plov-uzbekskiy"
  end

  test "clearing the slug regenerates it from the name", %{staff: staff, branch: branch} do
    {:ok, product} = Net.create_product(staff, branch.id, %{"name" => "Чай", "price" => 50})
    {:ok, updated} = Net.update_product(staff, product, %{"name" => "Чай чёрный", "slug" => ""})

    assert updated.slug == "chay-chernyy"
  end

  test "a taken slug typed by staff is a validation error", %{staff: staff, branch: branch} do
    {:ok, _} = Net.create_product(staff, branch.id, %{"name" => "Суп", "price" => 50})

    assert {:error, %Ecto.Changeset{errors: errors}} =
             Net.create_product(staff, branch.id, %{
               "name" => "Другой суп",
               "price" => 60,
               "slug" => "sup"
             })

    assert {_, [constraint: :unique, constraint_name: "products_slug_index"]} = errors[:slug]
  end

  test "branch product lookup by slug", %{staff: staff, branch: branch} do
    {:ok, product} = Net.create_product(staff, branch.id, %{"name" => "Хачапури", "price" => 400})

    assert Net.get_branch_product_by_slug(branch.id, "hachapuri").id == product.id
    assert Net.get_branch_product_by_slug(insert(:branch).id, "hachapuri") == nil
  end
end
