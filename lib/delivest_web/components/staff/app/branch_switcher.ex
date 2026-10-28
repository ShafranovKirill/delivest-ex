defmodule DelivestWeb.BranchSwitcher do
  use DelivestWeb, :html

  @searchable 7

  attr :current_branch, :map, default: nil
  attr :branches, :list, default: []
  attr :section, :string, default: nil

  def branch_switcher(assigns) do
    assigns =
      assign(assigns,
        to: assigns.section || "/dashboard",
        searchable: length(assigns.branches) > @searchable
      )

    ~H"""
    <div id="header-branch" class="dropdown dropdown-end flex-1 min-w-0 sm:flex-none">
      <div
        tabindex="0"
        role="button"
        class="flex items-center gap-2 h-10 cursor-pointer border border-base-300 py-1.5 px-2.5 sm:px-3 rounded-field hover:bg-base-200 transition-colors min-w-0"
      >
        <.icon name="hero-building-storefront" class="size-4 text-base-content/70 shrink-0" />
        <span
          class="text-sm font-medium text-base-content truncate sm:max-w-75 lg:max-w-none"
          title={@current_branch && @current_branch.name}
        >
          <%= if @current_branch do %>
            {@current_branch.name}
          <% else %>
            <span class="font-semibold">{gettext("No branch selected")}</span>
          <% end %>
        </span>
        <.icon name="hero-chevron-down" class="size-4 text-base-content/50 shrink-0" />
      </div>

      <div
        tabindex="0"
        id="header-branch-menu"
        phx-hook=".BranchFilter"
        class="dropdown-content z-1 mt-2 w-72 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg"
      >
        <label :if={@searchable} class="input input-sm mb-2 w-full">
          <.icon name="hero-magnifying-glass" class="size-4 text-base-content/50" />
          <input
            type="search"
            data-filter
            placeholder={gettext("Find a branch")}
            autocomplete="off"
            class="grow"
          />
        </label>

        <ul class="menu w-full max-h-80 flex-nowrap overflow-y-auto p-0">
          <li :for={branch <- @branches} data-name={String.downcase(branch.name)}>
            <.link
              id={"header-branch-#{branch.id}"}
              href={~p"/staff/branches/select/#{branch.id}?#{%{to: @to}}"}
              class={[@current_branch && @current_branch.id == branch.id && "menu-active"]}
            >
              <span class="truncate">{branch.name}</span>
              <.icon
                :if={@current_branch && @current_branch.id == branch.id}
                name="hero-check"
                class="ml-auto size-4 shrink-0"
              />
            </.link>
          </li>
          <li :if={@branches == []} class="px-3 py-2 text-sm text-base-content/60">
            {gettext("No branches available")}
          </li>
        </ul>
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".BranchFilter">
      export default {
        mounted() {
          this.el.addEventListener("input", (event) => {
            if (!event.target.matches("[data-filter]")) return
            const query = event.target.value.trim().toLowerCase()
            this.el.querySelectorAll("li[data-name]").forEach((item) => {
              item.hidden = query !== "" && !item.dataset.name.includes(query)
            })
          })
        }
      }
    </script>
    """
  end
end
