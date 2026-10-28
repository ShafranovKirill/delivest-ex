defmodule DelivestWeb.Staff.ProductLive.ProductTags do
  use DelivestWeb, :html

  alias Delivest.Net

  def without_blank(%{"tags" => tags} = params) when is_list(tags),
    do: %{params | "tags" => Enum.reject(tags, &(&1 == ""))}

  def without_blank(params), do: params

  attr :current, :atom, required: true

  def tabs(assigns) do
    assigns =
      assign(assigns,
        tabs: [
          {:products, ~p"/staff/products", "hero-cube", gettext("Products")},
          {:stops, ~p"/staff/products/stops", "hero-no-symbol", gettext("Stop list")},
          {:tags, ~p"/staff/products/tags", "hero-tag", gettext("Tags")},
          {:suggested, ~p"/staff/products/suggested", "hero-sparkles", gettext("Recommended")}
        ]
      )

    ~H"""
    <div role="tablist" class="tabs tabs-boxed w-fit max-w-full overflow-x-auto">
      <.link
        :for={{key, path, icon, label} <- @tabs}
        navigate={path}
        role="tab"
        class={["tab gap-2 whitespace-nowrap", @current == key && "tab-active font-bold"]}
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
        <.link navigate={~p"/staff/products/tags"} class="link">
          {gettext("Manage tags")}
        </.link>
      </p>
    </fieldset>
    """
  end

  defp selected(values) when is_list(values), do: Enum.map(values, &to_string/1)

  defp selected(_values), do: []
end
