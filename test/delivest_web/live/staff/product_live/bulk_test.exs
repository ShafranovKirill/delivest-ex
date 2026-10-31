defmodule DelivestWeb.Staff.ProductLive.BulkTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Net
  alias DelivestWeb.Staff.ProductLive.BulkRows

  setup %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    %{conn: conn, branch: branch}
  end

  test "pasted table with a header becomes products", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/products/bulk")

    text =
      "Название\tЦена\tКатегория\tВес, г\n" <>
        "Пепперони\t1 590,00 ₽\tПицца\t450 г\n" <>
        "Маргарита\t490\tпицца\t\n" <>
        "Кола\t120\tНапитки\t\n" <>
        "Морс\t90\tНапитки\t\n" <>
        "Сок\t100\tНапитки\t\n" <>
        "Чай\t60\tНапитки\t\n"

    lv
    |> element("#bulk-table")
    |> render_hook("paste", %{"row" => "1", "column" => "name", "text" => text})

    assert has_element?(lv, "#bulk-row-6")
    assert has_element?(lv, "#bulk-1-price[value='1 590,00 ₽']")

    products = ~p"/staff/b/#{branch}/products"

    assert {:error, {:live_redirect, %{to: ^products}}} =
             lv |> form("#bulk-products") |> render_submit()

    products = branch.id |> Net.list_branch_products() |> Map.new(&{&1.name, &1})
    assert map_size(products) == 6
    assert products["Пепперони"].price == 159_000
    assert products["Пепперони"].weight == 450
    assert products["Пепперони"].category_id == products["Маргарита"].category_id
  end

  test "photo from the last column is attached to the product", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/products/bulk")

    photo =
      file_input(lv, "#bulk-products", :bulk_photo_2, [
        %{name: "soup.jpg", content: "jpeg", type: "image/jpeg"}
      ])

    render_upload(photo, "soup.jpg")

    lv
    |> form("#bulk-products", rows: %{"2" => %{name: "Суп", price: "300"}})
    |> render_submit()

    assert [%{name: "Суп", media_id: media_id}] = Net.list_branch_products(branch.id)
    assert %{original_name: "soup.jpg", context: :product} = Delivest.Media.get_file(media_id)
  end

  test "invalid rows block saving and are highlighted", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/products/bulk")

    lv
    |> form("#bulk-products", rows: %{"1" => %{name: "Борщ", price: "дорого"}})
    |> render_submit()

    assert has_element?(lv, "#bulk-1-price.input-error")
    assert has_element?(lv, "#bulk-errors")
    assert Net.list_branch_products(branch.id) == []
  end

  test "parses prices, numbers and headers" do
    assert [%{"name" => "Борщ", "price" => "350"}, %{"name" => "Щи"}] =
             BulkRows.paste("Борщ\t350\r\nЩи\n\n", "name")

    assert [%{"price" => "400", "name" => "Плов"}] =
             BulkRows.paste("Цена\tНазвание\n400\tПлов", "name")

    assert {%{"price" => 150_000, "weight" => 300}, %{}} =
             BulkRows.validate(%{"name" => "Плов", "price" => "1 500 руб.", "weight" => "300гр"})

    assert {_attrs, %{"price" => _, "quantity" => _}} =
             BulkRows.validate(%{"name" => "Плов", "price" => "", "quantity" => "много"})
  end
end
