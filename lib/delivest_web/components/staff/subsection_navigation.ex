defmodule DelivestWeb.Staff.SubsectionNavigation do
  use DelivestWeb, :html

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :entries, :list, required: true
  attr :sidebar, :boolean, default: false

  def subsection_navigation(assigns) do
    ~H"""
    <ul :if={@sidebar} id={@id} phx-hook="ActiveSectionNav" aria-label={@label}>
      <li :for={entry <- @entries}>
        <.link
          id={entry.id}
          navigate={entry.path}
          class={entry.active && "menu-active"}
          aria-current={entry.active && "page"}
        >{entry.label}</.link>
      </li>
    </ul>
    <nav
      :if={!@sidebar}
      id={@id}
      phx-hook="ActiveSectionNav"
      aria-label={@label}
      class="tabs tabs-box max-w-full flex-nowrap overflow-x-auto whitespace-nowrap"
    >
      <.link
        :for={entry <- @entries}
        id={entry.id}
        navigate={entry.path}
        class={["tab shrink-0", entry.active && "tab-active"]}
        aria-current={entry.active && "page"}
      >{entry.label}</.link>
    </nav>
    """
  end

  attr :active, :atom, required: true

  slot :tab, required: true do
    attr :value, :atom, required: true
    attr :icon, :string
  end

  def integration_tabs(assigns) do
    ~H"""
    <div
      role="group"
      aria-label={gettext("Page sections")}
      class="tabs tabs-box w-fit max-w-full flex-nowrap overflow-x-auto"
    >
      <button
        :for={tab <- @tab}
        type="button"
        phx-click="tab"
        phx-value-tab={tab.value}
        aria-pressed={to_string(@active == tab.value)}
        class={[
          "tab shrink-0 gap-2 whitespace-nowrap",
          @active == tab.value && "tab-active font-bold"
        ]}
      >
        <.icon :if={tab[:icon]} name={tab.icon} class="size-4" />
        {render_slot(tab)}
      </button>
    </div>
    """
  end
end
