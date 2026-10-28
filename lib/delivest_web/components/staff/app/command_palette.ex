defmodule DelivestWeb.CommandPalette do
  use DelivestWeb, :html

  def command_palette_trigger(assigns) do
    ~H"""
    <button
      id="command-palette-trigger"
      type="button"
      phx-click={JS.dispatch("command-palette:open")}
      class={[
        "btn btn-ghost btn-sm btn-square sm:w-64 sm:justify-start sm:gap-2 sm:px-3",
        "sm:border-base-300 sm:bg-base-200/60 sm:font-normal sm:text-base-content/60"
      ]}
      aria-label={gettext("Search")}
    >
      <.icon name="hero-magnifying-glass" class="size-5 sm:size-4" />
      <span class="hidden sm:inline">{gettext("Search")}</span>
      <kbd
        id="command-palette-shortcut"
        phx-update="ignore"
        class="kbd kbd-sm ml-auto hidden sm:inline-flex"
      >
        Ctrl K
      </kbd>
    </button>
    """
  end

  attr :query, :string, required: true
  attr :groups, :list, required: true

  def command_palette(assigns) do
    ~H"""
    <div
      id="command-palette"
      phx-hook=".CommandPalette"
      data-open={show()}
      data-close={hide()}
      class="fixed inset-0 z-[60] hidden"
      role="dialog"
      aria-modal="true"
      aria-label={gettext("Search")}
    >
      <div class="absolute inset-0 bg-black/40" phx-click={hide()} aria-hidden="true"></div>

      <div class="relative mx-auto mt-[10vh] flex max-h-[70vh] w-[calc(100%-2rem)] max-w-xl flex-col overflow-hidden rounded-box border border-base-300 bg-base-100 shadow-2xl">
        <.form
          for={nil}
          id="command-palette-form"
          phx-change="command_search"
          class="flex items-center gap-3 border-b border-base-300 px-4"
        >
          <.icon name="hero-magnifying-glass" class="size-5 shrink-0 text-base-content/50" />
          <input
            id="command-palette-input"
            type="text"
            name="query"
            value={@query}
            phx-debounce="200"
            autocomplete="off"
            placeholder={gettext("Pages, orders, clients, products")}
            class="h-14 w-full bg-transparent outline-none placeholder:text-base-content/40"
          />
          <kbd class="kbd kbd-sm shrink-0">Esc</kbd>
        </.form>

        <div id="command-palette-results" class="overflow-y-auto overscroll-contain p-2">
          <div :for={group <- @groups} id={"command-group-#{group.id}"} class="pb-2">
            <p class="px-3 py-1.5 text-xs font-semibold uppercase tracking-wider text-base-content/50">
              {group.label}
            </p>
            <.link
              :for={item <- group.items}
              id={"command-item-#{item.id}"}
              navigate={item.path}
              data-command-item
              class="flex items-center gap-3 rounded-field px-3 py-2 data-active:bg-base-200 hover:bg-base-200"
            >
              <.icon name={item.icon} class="size-5 shrink-0 text-base-content/60" />
              <span class="truncate font-medium">{item.label}</span>
              <span :if={item.hint} class="ml-auto truncate text-sm text-base-content/50">
                {item.hint}
              </span>
            </.link>
          </div>

          <.empty_state
            :if={@groups == []}
            icon="hero-magnifying-glass"
            title={gettext("Nothing found")}
          />
        </div>
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CommandPalette">
      export default {
        mounted() {
          this.onShortcut = (event) => {
            if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
              event.preventDefault()
              this.open()
            }
          }
          this.onOpen = () => this.open()
          window.addEventListener("keydown", this.onShortcut)
          window.addEventListener("command-palette:open", this.onOpen)
          this.el.addEventListener("keydown", (event) => this.navigate(event))
          this.el.addEventListener("click", (event) => {
            if (event.target.closest("[data-command-item]")) this.close()
          })
          this.highlight(0)
          if (/Mac|iPhone|iPad/.test(navigator.platform))
            document.getElementById("command-palette-shortcut").textContent = "⌘K"
        },
        updated() {
          this.highlight(0)
        },
        destroyed() {
          window.removeEventListener("keydown", this.onShortcut)
          window.removeEventListener("command-palette:open", this.onOpen)
        },
        open() {
          this.liveSocket.execJS(this.el, this.el.dataset.open)
          requestAnimationFrame(() => this.el.querySelector("input").select())
        },
        close() {
          this.liveSocket.execJS(this.el, this.el.dataset.close)
        },
        items() {
          return [...this.el.querySelectorAll("[data-command-item]")]
        },
        highlight(index) {
          const items = this.items()
          this.index = Math.max(0, Math.min(index, items.length - 1))
          items.forEach((item, i) => item.toggleAttribute("data-active", i === this.index))
          items[this.index]?.scrollIntoView({ block: "nearest" })
        },
        navigate(event) {
          if (event.key === "Escape") return this.close()
          if (event.key === "ArrowDown" || event.key === "ArrowUp") {
            event.preventDefault()
            return this.highlight(this.index + (event.key === "ArrowDown" ? 1 : -1))
          }
          if (event.key === "Enter") {
            event.preventDefault()
            this.items()[this.index]?.click()
          }
        }
      }
    </script>
    """
  end

  defp show,
    do:
      JS.show(to: "#command-palette", display: "block")
      |> JS.focus(to: "#command-palette-input")
      |> JS.add_class("overflow-hidden", to: "body")

  defp hide,
    do:
      JS.hide(to: "#command-palette")
      |> JS.remove_class("overflow-hidden", to: "body")
end
