defmodule DelivestWeb.Staff.CollectionsNavigation do
  use DelivestWeb, :html

  attr :branch, :any, required: true
  attr :active, :atom, required: true

  def collections_navigation(assigns) do
    ~H"""
    <nav aria-label={gettext("Collections")} class="flex max-w-full flex-wrap items-center gap-1">
      <.link
        id="collections-tab-popular"
        navigate={~p"/staff/b/#{@branch}/menu/popular"}
        aria-current={@active == :popular && "page"}
        class={["btn btn-sm", if(@active == :popular, do: "btn-primary", else: "btn-outline")]}
      >{gettext("Popular products")}</.link>
      <.link
        id="collections-tab-suggested"
        navigate={~p"/staff/b/#{@branch}/products/suggested"}
        aria-current={@active == :suggested && "page"}
        class={["btn btn-sm", if(@active == :suggested, do: "btn-primary", else: "btn-outline")]}
      >{gettext("Recommended")}</.link>
    </nav>
    """
  end
end
