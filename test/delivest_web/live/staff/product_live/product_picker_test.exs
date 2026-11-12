defmodule DelivestWeb.Staff.ProductLive.ProductPickerTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defp products do
    [
      %{id: "a", name: "Apple", category: %{name: "Fruit"}},
      %{id: "b", name: "Banana", category: %{name: "Fruit"}},
      %{id: "c", name: "Carrot", category: %{name: "Vegetables"}}
    ]
  end

  test "draft survives search and parent refresh, cancel discards it", %{conn: conn} do
    {:ok, view, _} =
      live_isolated(conn, DelivestWeb.Test.ProductPickerHost,
        session: %{"products" => products(), "mode" => :multiple}
      )

    refute has_element?(view, "#test-picker-product-a")

    view
    |> element("#test-picker button[phx-value-category=Fruit][phx-click=collapse]")
    |> render_click()

    view |> element("#test-picker-product-a input") |> render_click()
    view |> form("#test-picker-search", %{search: "car"}) |> render_change()
    assert has_element?(view, "#test-picker-product-c")
    view |> element("#refresh-host") |> render_click()
    view |> form("#test-picker-search", %{search: "apple"}) |> render_change()
    assert has_element?(view, "#test-picker-product-a input[checked]")
    view |> element("#test-picker button.btn-outline[phx-click=cancel]") |> render_click()
    render(view)
    view |> element("#open-picker") |> render_click()

    view
    |> element("#test-picker button[phx-value-category=Fruit][phx-click=collapse]")
    |> render_click()

    refute has_element?(view, "#test-picker-product-a input[checked]")
  end

  test "single mode clears draft and saves at most one", %{conn: conn} do
    {:ok, view, _} =
      live_isolated(conn, DelivestWeb.Test.ProductPickerHost,
        session: %{"products" => products(), "mode" => :single, "selected_ids" => ["a", "b"]}
      )

    refute has_element?(view, "#test-picker input[phx-click=category_all]")
    view |> element("#test-picker button[phx-click=clear]") |> render_click()

    view
    |> element("#test-picker button[phx-value-category=Fruit][phx-click=collapse]")
    |> render_click()

    view |> element("#test-picker-product-b input") |> render_click()
    view |> element("#test-picker button[phx-click=save]") |> render_click()
    assert has_element?(view, "#picker-result", ~s(["b"]))
  end
end
