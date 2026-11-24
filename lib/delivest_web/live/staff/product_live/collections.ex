defmodule DelivestWeb.Staff.ProductLive.Collections do
  use DelivestWeb, :live_view

  on_mount {DelivestWeb.Hooks.Permission, "products.read"}

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, page_title: gettext("Collections"))}

  def staff_page_header(assigns) do
    ~H"""
    <.page_toolbar id="collections-toolbar" title={gettext("Collections")} />
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="collections-overview" class="grid gap-4 sm:grid-cols-2">
      <section
        id="collections-popular"
        class="flex flex-col gap-4 rounded-box border border-base-300 bg-base-100 p-5 shadow-sm"
      >
        <div class="flex items-start gap-3">
          <span class="rounded-lg bg-primary/10 p-2 text-primary"><.icon
            name="hero-fire"
            class="size-5"
          /></span>
          <div>
            <h2 class="text-lg font-semibold">{gettext("Popular products")}</h2>
            <p class="mt-1 text-sm text-base-content/70">
              {gettext(
                "Build a popular selection manually or from sales over the last 30 days. Choose where customers see it."
              )}
            </p>
          </div>
        </div>
        <.link
          navigate={~p"/staff/b/#{@current_branch}/menu/popular"}
          class="btn btn-outline btn-sm mt-auto self-start"
        >
          {gettext("Popular products")}
          <.icon name="hero-arrow-right" class="size-4" />
        </.link>
      </section>
      <section
        id="collections-suggested"
        class="flex flex-col gap-4 rounded-box border border-base-300 bg-base-100 p-5 shadow-sm"
      >
        <div class="flex items-start gap-3">
          <span class="rounded-lg bg-primary/10 p-2 text-primary"><.icon
            name="hero-sparkles"
            class="size-5"
          /></span>
          <div>
            <h2 class="text-lg font-semibold">{gettext("Recommended")}</h2>
            <p class="mt-1 text-sm text-base-content/70">
              {gettext("Choose products to recommend to customers.")}
            </p>
          </div>
        </div>
        <.link
          navigate={~p"/staff/b/#{@current_branch}/products/suggested"}
          class="btn btn-outline btn-sm mt-auto self-start"
        >
          {gettext("Recommended")}
          <.icon name="hero-arrow-right" class="size-4" />
        </.link>
      </section>
    </div>
    """
  end
end
