defmodule DelivestWeb.ErrorHTMLTest do
  use DelivestWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    html = render_to_string(DelivestWeb.ErrorHTML, "404", "html", [])
    assert html =~ "<h1>Page not found</h1>"
    assert html =~ ~s(href="/")
    assert html =~ "prefers-color-scheme: dark"
  end

  test "renders 500.html" do
    html = render_to_string(DelivestWeb.ErrorHTML, "500", "html", [])
    assert html =~ "<h1>Something went wrong!</h1>"
    assert html =~ ~s(href="/")
  end

  test "uses the selected session locale for an error page", %{conn: conn} do
    conn = init_test_session(conn, %{"locale" => "ru"})

    html = render_to_string(DelivestWeb.ErrorHTML, "404", "html", conn: conn)

    assert html =~ "<h1>Раздел не найден</h1>"
    assert html =~ ">На главную</a>"
  end
end
