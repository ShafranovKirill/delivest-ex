defmodule DelivestWeb.Staff.ProductLive.ProductPicker do
  @moduledoc """
  Reusable, ephemeral product selection dialog. The parent passes branch products
  with preloaded `:category`, `selected_ids`, `mode` (`:multiple` or `:single`),
  `on_save` (arity 1, ordered IDs), and `on_cancel` (arity 0). Render it only while
  open and outside parent forms. The opener uses `JS.push_focus()` before
  `JS.push/2` to open it; the dialog focuses its first control and restores
  opener focus when removed. Selection stays in memory until Save; the parent
  validates permissions and product ownership before persisting.
  """

  use DelivestWeb, :live_component

  alias Phoenix.LiveView.JS

  @impl true
  def update(assigns, socket) do
    assigns =
      assigns |> Map.put_new(:mode, :multiple) |> Map.put_new(:title, gettext("Add products"))

    valid_ids = MapSet.new(Enum.map(assigns.products, & &1.id))
    selected = assigns.selected_ids |> Enum.uniq() |> Enum.filter(&MapSet.member?(valid_ids, &1))
    selected = if assigns.mode == :single, do: Enum.take(selected, 1), else: selected

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:draft_ids, fn -> selected end)
     |> assign_new(:search, fn -> "" end)
     |> assign_new(:only_selected, fn -> false end)
     |> assign_new(:collapsed, fn -> MapSet.new(Enum.map(assigns.products, &category_name/1)) end)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket),
    do: {:noreply, assign(socket, search: search)}

  def handle_event("filter", %{"selected" => selected}, socket),
    do: {:noreply, assign(socket, only_selected: selected == "true")}

  def handle_event("collapse", %{"category" => category}, socket) do
    collapsed = socket.assigns.collapsed

    collapsed =
      if MapSet.member?(collapsed, category),
        do: MapSet.delete(collapsed, category),
        else: MapSet.put(collapsed, category)

    {:noreply, assign(socket, collapsed: collapsed)}
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.products, &(&1.id == id)) do
      ids = socket.assigns.draft_ids

      ids =
        cond do
          id in ids and socket.assigns.mode == :single -> ids
          id in ids -> List.delete(ids, id)
          socket.assigns.mode == :single -> [id]
          true -> ids ++ [id]
        end

      {:noreply, assign(socket, draft_ids: ids)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("category_all", %{"category" => category}, socket) do
    if socket.assigns.mode == :single,
      do: {:noreply, socket},
      else: toggle_category(socket, category)
  end

  def handle_event("save", _params, socket) do
    valid = MapSet.new(Enum.map(socket.assigns.products, & &1.id))
    ids = Enum.filter(socket.assigns.draft_ids, &MapSet.member?(valid, &1))
    ids = if socket.assigns.mode == :single, do: Enum.take(ids, 1), else: ids
    socket.assigns.on_save.(ids)
    {:noreply, socket}
  end

  def handle_event("cancel", _params, socket) do
    socket.assigns.on_cancel.()
    {:noreply, socket}
  end

  def handle_event("clear", _params, socket) do
    if socket.assigns.mode == :single,
      do: {:noreply, assign(socket, draft_ids: [])},
      else: {:noreply, socket}
  end

  defp toggle_category(socket, category) do
    visible =
      socket.assigns
      |> visible_products()
      |> Enum.filter(&(category_name(&1) == category))
      |> Enum.map(& &1.id)

    ids = socket.assigns.draft_ids

    ids =
      if Enum.all?(visible, &(&1 in ids)),
        do: ids -- visible,
        else: ids ++ Enum.reject(visible, &(&1 in ids))

    {:noreply, assign(socket, draft_ids: ids)}
  end

  defp visible_products(assigns) do
    search = assigns.search |> String.trim() |> String.downcase()

    Enum.filter(assigns.products, fn product ->
      (not assigns.only_selected or product.id in assigns.draft_ids) and
        (search == "" or String.contains?(String.downcase(product.name), search))
    end)
  end

  defp category_name(%{category: %{name: name}}), do: name
  defp category_name(_), do: gettext("Without category")

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        searching: String.trim(assigns.search) != "",
        groups:
          assigns
          |> visible_products()
          |> Enum.group_by(&category_name/1)
          |> Enum.sort_by(&elem(&1, 0))
      )

    ~H"""
    <div
      id={@id}
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
      class="modal modal-open"
      phx-window-keydown={JS.push("cancel", target: @myself)}
      phx-key="escape"
      phx-mounted={JS.focus_first(to: "##{@id}-focus")}
      phx-remove={JS.pop_focus()}
    >
      <.focus_wrap
        id={"#{@id}-focus"}
        class="modal-box flex max-h-[85dvh] max-w-4xl flex-col gap-4"
      >
        <div class="flex items-center justify-between">
          <h2 id={"#{@id}-title"} class="shrink-0 text-lg font-bold">{@title}</h2><button
            type="button"
            aria-label={gettext("Close")}
            phx-click="cancel"
            phx-target={@myself}
            class="btn btn-ghost btn-sm"
          ><.icon name="hero-x-mark" class="size-5" /></button>
        </div>
        <div class="shrink-0 space-y-3 pt-3">
          <.form for={nil} id={"#{@id}-search"} phx-change="search" phx-target={@myself}>
            <.input
              type="text"
              name="search"
              value={@search}
              placeholder={gettext("Search products...")}
              phx-debounce="300"
            />
          </.form>
          <.form for={nil} id={"#{@id}-filter"} phx-change="filter" phx-target={@myself}>
            <label class="flex items-center gap-2">
              <input type="hidden" name="selected" value="false" />
              <input
                type="checkbox"
                name="selected"
                value="true"
                checked={@only_selected}
                class="checkbox checkbox-primary checkbox-sm"
              />
              {gettext("Only selected")}
            </label>
          </.form>
        </div>
        <div id={"#{@id}-categories"} class="min-h-0 overflow-y-auto">
          <p :if={@groups == []} class="py-6 text-center text-sm text-base-content/60">
            {gettext("No products")}
          </p>
          <section
            :for={{category, products} <- @groups}
            id={"#{@id}-category-#{category}"}
            class="border-b border-base-300 py-2"
          >
            <div class="flex items-center gap-2">
              <input
                :if={@mode == :multiple}
                type="checkbox"
                class="checkbox checkbox-primary checkbox-sm"
                checked={Enum.all?(products, &(&1.id in @draft_ids))}
                aria-checked={
                  if Enum.any?(products, &(&1.id in @draft_ids)) and
                       not Enum.all?(products, &(&1.id in @draft_ids)),
                     do: "mixed",
                     else: Enum.all?(products, &(&1.id in @draft_ids))
                }
                phx-click="category_all"
                phx-target={@myself}
                phx-value-category={category}
                aria-label={gettext("Select all in %{category}", category: category)}
              />
              <button
                type="button"
                phx-click="collapse"
                phx-target={@myself}
                phx-value-category={category}
                aria-expanded={@searching or not MapSet.member?(@collapsed, category)}
                class="font-bold"
              >{if @searching or not MapSet.member?(@collapsed, category), do: "⌄", else: "›"} {category} ({Enum.count(
                products,
                &(&1.id in @draft_ids)
              )}/{length(products)})</button>
            </div>
            <ul :if={@searching or not MapSet.member?(@collapsed, category)} class="space-y-1 pl-6">
              <li :for={product <- products} id={"#{@id}-product-#{product.id}"}>
                <label class="flex cursor-pointer items-center gap-2 py-1">
                  <input
                    type={if @mode == :single, do: "radio", else: "checkbox"}
                    class={
                      if @mode == :single,
                        do: "radio radio-primary radio-sm",
                        else: "checkbox checkbox-primary checkbox-sm"
                    }
                    name={"#{@id}-selection"}
                    checked={product.id in @draft_ids}
                    phx-click="toggle"
                    phx-target={@myself}
                    phx-value-id={product.id}
                  />
                  {product.name}
                </label>
              </li>
            </ul>
          </section>
        </div>
        <div class="flex shrink-0 flex-wrap items-center justify-between gap-2 border-t border-base-300 pt-3">
          <span class="text-sm">{gettext("Selected")}: {length(@draft_ids)}</span>
          <button
            :if={@mode == :single and @draft_ids != []}
            type="button"
            class="btn btn-ghost"
            phx-click="clear"
            phx-target={@myself}
          >{gettext("Clear selection")}</button>
          <div class="ml-auto flex gap-2">
            <button type="button" class="btn btn-outline" phx-click="cancel" phx-target={@myself}>{gettext(
              "Cancel"
            )}</button>
            <button type="button" class="btn btn-primary" phx-click="save" phx-target={@myself}>
              {gettext("Add selected")}
            </button>
          </div>
        </div>
      </.focus_wrap>
      <div class="modal-backdrop bg-black/50" phx-click={JS.push("cancel", target: @myself)}></div>
    </div>
    """
  end
end
