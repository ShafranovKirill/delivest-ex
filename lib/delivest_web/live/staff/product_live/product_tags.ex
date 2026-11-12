defmodule DelivestWeb.Staff.ProductLive.ProductTags do
  use DelivestWeb, :html

  alias Delivest.Net
  alias Delivest.Identity
  alias DelivestWeb.StaffBranchPath

  def section(path) when is_binary(path) do
    case StaffBranchPath.strip(path) do
      "/staff/menu/popular" -> :popular
      "/staff/products" -> :products
      "/staff/products/" <> rest -> section_suffix(rest)
      _ -> nil
    end
  end

  def section(_path), do: nil

  def actions?(section, staff) when section in [:modifiers, :tags],
    do: Identity.can?(staff, "catalog.global.manage")

  def actions?(:popular, staff), do: Identity.can?(staff, "products.update")

  def actions?(section, _staff) when section in [:products, :bulk], do: true
  def actions?(_section, _staff), do: false

  defp section_suffix(rest) do
    case String.split(rest, "/", trim: true) do
      ["operations" | _] -> nil
      ["stops" | _] -> :stops
      ["modifiers" | _] -> :modifiers
      ["tags" | _] -> :tags
      ["suggested" | _] -> :suggested
      ["bulk" | _] -> :bulk
      [_ | _] -> :products
      [] -> :products
    end
  end

  def without_blank(%{"tags" => tags} = params) when is_list(tags),
    do: %{params | "tags" => Enum.reject(tags, &(&1 == ""))}

  def without_blank(params), do: params

  attr :current, :atom, required: true
  attr :branch, :any, required: true

  def tabs(assigns) do
    assigns =
      assign(assigns,
        tabs: [
          {:products, ~p"/staff/b/#{assigns.branch}/products", "hero-cube", gettext("Products")},
          {:stops, ~p"/staff/b/#{assigns.branch}/products/stops", "hero-no-symbol",
           gettext("Stop list")},
          {:modifiers, ~p"/staff/b/#{assigns.branch}/products/modifiers",
           "hero-adjustments-horizontal", gettext("Modifiers")},
          {:tags, ~p"/staff/b/#{assigns.branch}/products/tags", "hero-tag", gettext("Tags")},
          {:suggested, ~p"/staff/b/#{assigns.branch}/products/suggested", "hero-sparkles",
           gettext("Recommended")},
          {:popular, ~p"/staff/b/#{assigns.branch}/menu/popular", "hero-fire",
           gettext("Popular products")}
        ]
      )

    ~H"""
    <div role="tablist" class="tabs w-fit max-w-full overflow-x-auto">
      <.link
        :for={{key, path, icon, label} <- @tabs}
        id={"product-section-tab-#{key}"}
        data-section={key}
        navigate={path}
        role="tab"
        aria-current={if @current == key, do: "page"}
        aria-selected={if @current == key, do: "true", else: "false"}
        class={["tab gap-2 whitespace-nowrap", @current == key && "tab-active"]}
      >
        <.icon name={icon} class="size-4" /> {label}
      </.link>
    </div>
    """
  end

  attr :tag, :any, required: true
  attr :class, :string, default: "size-5"

  def tag_icon(assigns) do
    assigns = assign(assigns, :url, Net.product_tag_icon_url(assigns.tag))

    ~H"""
    <img :if={@url} src={@url} alt="" class={["object-contain", @class]} />
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :tags, :list, required: true
  attr :branch, :any, required: true

  def tag_checkboxes(assigns) do
    assigns = assign(assigns, selected: selected(assigns.field.value))

    ~H"""
    <fieldset class="space-y-2">
      <legend class="label-text font-bold">{gettext("Tags")}</legend>
      <input type="hidden" name={@field.name <> "[]"} value="" />
      <div class="flex flex-wrap gap-2">
        <label
          :for={tag <- @tags}
          class="flex items-center gap-2 rounded-full border border-base-300 px-3 py-1.5 cursor-pointer has-checked:border-primary has-checked:bg-primary/10"
        >
          <input
            type="checkbox"
            name={@field.name <> "[]"}
            value={tag.id}
            checked={tag.id in @selected}
            class="checkbox checkbox-xs checkbox-primary"
          />
          <.tag_icon tag={tag} class="size-4" />
          <span class="text-sm">{tag.name}</span>
        </label>
      </div>
      <p class="text-xs text-base-content/60">
        {gettext("Shown on the product card on the website.")}
        <.link navigate={~p"/staff/b/#{@branch}/products/tags"} class="link">
          {gettext("Manage tags")}
        </.link>
      </p>
    </fieldset>
    """
  end

  defp selected(values) when is_list(values), do: Enum.map(values, &to_string/1)

  defp selected(_values), do: []
end
