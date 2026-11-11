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
    <details id="header-branch" class="group/branch relative w-full min-w-0">
      <summary
        aria-label={if @current_branch, do: @current_branch.name, else: gettext("No branch selected")}
        aria-controls="header-branch-menu"
        title={if @current_branch, do: @current_branch.name, else: gettext("No branch selected")}
        class="staff-branch-trigger flex w-full min-w-0 cursor-pointer list-none items-center gap-2 rounded-field border border-base-300 px-2.5 py-2 hover:bg-base-200 [&::-webkit-details-marker]:hidden"
      >
        <.icon name="hero-building-storefront" class="size-4 text-base-content/70 shrink-0" />
        <span
          class="staff-sidebar-label truncate text-sm font-medium text-base-content"
          title={@current_branch && @current_branch.name}
        >
          <%= if @current_branch do %>
            {@current_branch.name}
          <% else %>
            <span class="font-semibold">{gettext("No branch selected")}</span>
          <% end %>
        </span>
        <.icon
          name="hero-chevron-down"
          class="staff-sidebar-label size-4 shrink-0 text-base-content/50 group-open/branch:rotate-180"
        />
      </summary>

      <div
        id="header-branch-menu"
        phx-hook=".BranchFilter"
        class="staff-branch-menu absolute left-0 top-full z-[70] mt-2 w-72 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg"
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
    </details>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".BranchFilter">
      export default {
        mounted() {
          this.details = this.el.closest("details")
          this.onInput = (event) => {
            if (!event.target.matches("[data-filter]")) return
            const query = event.target.value.trim().toLowerCase()
            this.el.querySelectorAll("li[data-name]").forEach((item) => {
              item.hidden = query !== "" && !item.dataset.name.includes(query)
            })
          }
          this.onKeyDown = (event) => {
            if (event.key !== "Escape" || !this.details.open) return
            this.details.open = false
            this.details.querySelector("summary").focus()
            event.preventDefault()
          }
          this.onOutsideClick = (event) => {
            if (this.details.open && !this.details.contains(event.target)) this.details.open = false
          }
          this.el.addEventListener("input", this.onInput)
          this.details.addEventListener("keydown", this.onKeyDown)
          document.addEventListener("click", this.onOutsideClick)
        },
        destroyed() {
          this.el.removeEventListener("input", this.onInput)
          this.details.removeEventListener("keydown", this.onKeyDown)
          document.removeEventListener("click", this.onOutsideClick)
        }
      }
    </script>
    """
  end
end
