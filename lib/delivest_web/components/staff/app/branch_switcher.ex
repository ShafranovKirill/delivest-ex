defmodule DelivestWeb.BranchSwitcher do
  use DelivestWeb, :html

  @searchable 7

  attr :current_branch, :map, default: nil
  attr :branches, :list, default: []
  attr :section, :string, default: nil
  attr :from, :string, default: nil
  attr :aggregate, :boolean, default: false

  def branch_switcher(assigns) do
    source = assigns.from || "/staff/dashboard"
    network = DelivestWeb.StaffBranchPath.transition(source, :network)

    branch_links =
      Enum.map(assigns.branches, fn branch ->
        transition = DelivestWeb.StaffBranchPath.transition(source, {:branch, branch.slug})
        {branch, switch_path(branch.id, source, transition), switch_label(transition)}
      end)

    assigns =
      assign(assigns,
        branch_links: branch_links,
        network_path: network_path(source, network),
        network_choice: match?({:choice, _}, network),
        network_label: network_label(network),
        scope_label:
          if(assigns.current_branch,
            do: assigns.current_branch.name,
            else:
              if(assigns.aggregate,
                do: gettext("All accessible branches"),
                else: gettext("Network")
              )
          ),
        searchable: length(assigns.branches) > @searchable
      )

    ~H"""
    <details id="header-branch" class="group/branch relative w-full min-w-0">
      <summary
        aria-label={@scope_label}
        aria-controls="header-branch-menu"
        title={@scope_label}
        class="staff-branch-trigger flex w-full min-w-0 cursor-pointer list-none items-center gap-2 rounded-field border border-base-300 px-2.5 py-2 hover:bg-base-200 [&::-webkit-details-marker]:hidden"
      >
        <.icon name="hero-building-storefront" class="size-4 text-base-content/70 shrink-0" />
        <span
          class="staff-sidebar-label truncate text-sm font-medium text-base-content"
          title={@scope_label}
        >
          <%= if @current_branch do %>
            {@current_branch.name}
          <% else %>
            <span class="font-semibold">{@scope_label}</span>
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
          <li data-name={String.downcase(gettext("All branches"))}>
            <.link
              id="header-branch-all"
              href={@network_path}
              class={[is_nil(@current_branch) && "menu-active"]}
            >
              {@network_label}
            </.link>
          </li>
          <li :if={@network_choice}>
            <.link href={@from || "/staff/dashboard"}>{gettext("Stay in this branch")}</.link>
          </li>
          <li :for={{branch, path, label} <- @branch_links} data-name={String.downcase(branch.name)}>
            <.link
              id={"header-branch-#{branch.id}"}
              href={path}
              class={[@current_branch && @current_branch.id == branch.id && "menu-active"]}
            >
              <span class="truncate">{branch.name}</span>
              <span :if={label} class="text-xs text-base-content/60">· {label}</span>
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

  defp network_path(source, {:ok, _}), do: ~p"/staff/branches/all?#{%{from: source}}"

  defp network_path(source, {:choice, _}),
    do: ~p"/staff/branches/all?#{%{from: source, fallback: "overview"}}"

  defp network_path(_source, _), do: ~p"/staff/branches/all"

  defp switch_path(id, source, {:ok, _}),
    do: ~p"/staff/branches/select/#{id}?#{%{from: source}}"

  defp switch_path(id, source, {:fallback, _}),
    do: ~p"/staff/branches/select/#{id}?#{%{from: source, fallback: "overview"}}"

  defp switch_path(id, _source, _), do: ~p"/staff/branches/select/#{id}?#{%{to: "/dashboard"}}"

  defp switch_label({:fallback, %{label: label}}), do: label
  defp switch_label({:ok, _}), do: nil
  defp switch_label(_), do: gettext("Overview of the branch")

  defp network_label({:choice, _}), do: gettext("Overview of the network")
  defp network_label({:ok, %{path: "/staff/dashboard"}}), do: gettext("All accessible branches")
  defp network_label({:ok, _}), do: gettext("Network")
  defp network_label(_), do: gettext("Overview of the network")
end
