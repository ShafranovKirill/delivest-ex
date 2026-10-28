defmodule DelivestWeb.Staff.ProductLive.BranchProducts do
  use DelivestWeb, :html

  alias Delivest.{Net, Repo}

  def load(branch_id), do: branch_id |> Net.list_branch_products() |> Repo.preload(:category)

  def filter(products, search, keep?) do
    query = search |> to_string() |> String.trim() |> String.downcase()

    Enum.filter(products, fn product ->
      keep?.(product) and (query == "" or String.contains?(String.downcase(product.name), query))
    end)
  end

  attr :id, :string, required: true
  attr :search, :string, required: true
  attr :only, :boolean, required: true
  attr :only_label, :string, required: true

  def filter_form(assigns) do
    ~H"""
    <.form for={nil} id={@id} phx-change="filter" class="flex flex-wrap items-center gap-4">
      <div class="relative w-full sm:max-w-sm">
        <.icon
          name="hero-magnifying-glass"
          class="absolute left-3 top-3.5 size-5 text-base-content/50 z-10"
        />
        <.input
          type="text"
          name="search"
          value={@search}
          placeholder={gettext("Search products...")}
          class="input input-bordered w-full pl-10"
          phx-debounce="300"
        />
      </div>
      <label class="flex cursor-pointer items-center gap-2">
        <input type="hidden" name="only" value="false" />
        <input type="checkbox" name="only" value="true" checked={@only} class="toggle toggle-sm" />
        <span class="text-sm">{@only_label}</span>
      </label>
    </.form>
    """
  end

  attr :id, :string, required: true
  attr :products, :list, required: true
  attr :empty, :string, required: true
  slot :action, required: true

  def product_list(assigns) do
    assigns = assign(assigns, groups: Enum.group_by(assigns.products, &category_name/1))

    ~H"""
    <div id={@id} class="space-y-4">
      <p :if={@products == []} class="py-10 text-center text-base-content/60">{@empty}</p>

      <section
        :for={{category, products} <- Enum.sort_by(@groups, &elem(&1, 0))}
        class="rounded-box border border-base-300 bg-base-100"
      >
        <h2 class="border-b border-base-300 px-4 py-2 text-xs font-black uppercase tracking-widest text-base-content/50">
          {category}
        </h2>
        <ul class="divide-y divide-base-200">
          <li
            :for={product <- products}
            id={"#{@id}-#{product.id}"}
            class="flex flex-wrap items-center justify-between gap-2 px-4 py-2"
          >
            <span class="font-bold">{product.name}</span>
            {render_slot(@action, product)}
          </li>
        </ul>
      </section>
    </div>
    """
  end

  defp category_name(%{category: %{name: name}}), do: name
  defp category_name(_product), do: gettext("Without category")
end
