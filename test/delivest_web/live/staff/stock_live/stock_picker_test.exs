defmodule DelivestWeb.Staff.StockLive.StockPickerTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.{Net, Repo}
  alias Delivest.Media.File

  test "linked product picker preserves banner draft on cancel and save", %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    branch = insert(:branch)
    product = insert_branch_product(branch.id, name: "Cola")

    media =
      %File{}
      |> File.changeset(%{
        bucket: "test",
        key: "stock-picker-#{Ecto.UUID.generate()}.png",
        original_name: "banner.png",
        mime_type: "image/png",
        size: 100,
        context: :stock,
        owner_id: staff.id
      })
      |> Repo.insert!()

    {:ok, stock} =
      Net.create_stock(staff, branch.id, %{"media_id" => media.id, "text" => "Original"})

    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/stocks/#{stock.id}/edit")

    lv |> form("#stock-form", stock: %{text: "Draft banner"}) |> render_change()
    lv |> element("#stock-open-product-picker") |> render_click()
    assert has_element?(lv, "#stock-product-picker")
    lv |> element("#stock-product-picker button.btn-outline[phx-click=cancel]") |> render_click()
    assert has_element?(lv, ~s(#stock-form textarea[name="stock[text]"]), "Draft banner")
    refute has_element?(lv, "#stock-product-picker")

    lv |> element("#stock-open-product-picker") |> render_click()
    lv |> form("#stock-product-picker-search", search: "Cola") |> render_change()

    lv
    |> element("#stock-product-picker-product-#{product.id} input[phx-click=toggle]")
    |> render_click()

    lv |> element("#stock-product-picker button[phx-click=save]") |> render_click()

    assert has_element?(
             lv,
             ~s(#stock-form input[name="stock[product_id]"][value="#{product.id}"])
           )

    assert has_element?(lv, ~s(#stock-form input[name="stock[media_id]"][value="#{media.id}"]))

    lv |> form("#stock-form", stock: %{text: "Final banner"}) |> render_submit()
    assert Repo.reload!(stock).product_id == product.id
    assert Repo.reload!(stock).text == "Final banner"
    assert Repo.reload!(stock).media_id == media.id
  end
end
