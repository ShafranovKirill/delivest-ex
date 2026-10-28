defmodule DelivestWeb.Staff.ProductLive.TagsTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Net
  alias Delivest.Net.ProductTag
  alias Delivest.Repo

  setup %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    %{conn: conn, staff: staff, branch: branch}
  end

  test "default tags are created with library icons", %{conn: conn, branch: branch} do
    names = Enum.map(Net.list_product_tags(), & &1.name)
    assert names == ["Хит", "Новинка", "Острое", "Вегетарианское", "Детям", "Выгодно"]

    {:ok, _lv, html} = live(conn, ~p"/staff/b/#{branch}/products/tags")
    assert html =~ "Вегетарианское"
    assert html =~ "/images/tag-icons/leaf.svg"
  end

  test "a tag is created with a picked icon and edited", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/products/tags/new")

    lv
    |> form("#product-tag-form", product_tag: %{name: "Без глютена", icon: "wheat-off"})
    |> render_submit()

    tag = Repo.get_by!(ProductTag, name: "Без глютена")
    assert tag.icon == "wheat-off"
    assert render(lv) =~ "Без глютена"

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/products/tags/#{tag.id}/edit")

    lv
    |> form("#product-tag-form", product_tag: %{name: "Без лактозы", icon: "milk-off"})
    |> render_submit()

    assert %{name: "Без лактозы", icon: "milk-off"} = Repo.get!(ProductTag, tag.id)
  end

  test "a tag needs a name and a known icon", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/products/tags/new")

    html =
      lv
      |> form("#product-tag-form", product_tag: %{name: "", icon: "star"})
      |> render_submit()

    assert html =~ "can&#39;t be blank"

    assert {:error, changeset} =
             Net.create_product_tag(insert_admin(), %{name: "X", icon: "nope"})

    assert [icon: _] = changeset.errors
  end

  test "deleting a tag removes it from products", %{conn: conn, staff: staff, branch: branch} do
    tag = Repo.get_by!(ProductTag, name: "Хит")
    keep = Repo.get_by!(ProductTag, name: "Острое")

    {:ok, product} =
      Net.create_product(staff, branch.id, %{
        "name" => "Пепперони",
        "price" => 500,
        "tags" => [tag.id, keep.id]
      })

    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/products/tags")
    lv |> element("#product-tag-#{tag.id} button[phx-click=delete_click]") |> render_click()
    lv |> element("#delete-product-tag-modal button.btn-error") |> render_click()

    refute Repo.get(ProductTag, tag.id)
    assert Net.Products.get_product(product.id).tags == [keep.id]
  end

  test "staff without product editing cannot manage tags", %{conn: conn, branch: branch} do
    staff = insert(:staff, role: insert(:role, permissions: ["products.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    {:ok, _lv, html} = live(conn, ~p"/staff/b/#{branch}/products/tags")
    refute html =~ "Add tag"
    assert {:error, {:live_redirect, _}} = live(conn, ~p"/staff/b/#{branch}/products/tags/new")
    assert {:error, :forbidden} = Net.create_product_tag(staff, %{name: "X", icon: "star"})
  end

  test "an uploaded icon is shrunk to a small 64px png" do
    {:ok, image} = Vix.Vips.Operation.black(512, 512, bands: 4)
    {:ok, big} = Vix.Vips.Image.write_to_buffer(image, ".png")

    {:ok, png} = Delivest.Net.ProductTags.shrink(big)
    {:ok, small} = Vix.Vips.Image.new_from_buffer(png)

    assert {64, 64} == {Vix.Vips.Image.width(small), Vix.Vips.Image.height(small)}
    assert {:error, :invalid_image} = Delivest.Net.ProductTags.shrink("not an image")
  end

  defp insert_admin, do: insert(:staff, role: insert(:role, permissions: ["admin"]))
end
