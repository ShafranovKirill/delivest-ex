defmodule DelivestWeb.PortalTestHelper do
  import Phoenix.LiveViewTest, only: [element: 2, has_element?: 2, render: 1]

  def has_element?(view, portal_id, selector, text \\ nil) do
    if has_element?(view, portal_id),
      do: portal_has_element?(view, portal_id, selector, text),
      else: false
  end

  defp portal_has_element?(view, portal_id, selector, text) do
    portal =
      view
      |> element(portal_id)
      |> render()
      |> then(&Regex.run(~r/<template[^>]*>(.*)<\/template>/s, &1))
      |> case do
        [_, content] -> LazyHTML.from_fragment(content)
        _ -> LazyHTML.from_fragment("")
      end

    portal
    |> LazyHTML.query(selector)
    |> Enum.any?(fn match -> is_nil(text) or String.contains?(LazyHTML.text(match), text) end)
  end
end
