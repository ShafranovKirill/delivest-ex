defmodule DelivestWeb.Staff.LogLive.Components.TabsComponent do
  use DelivestWeb, :html

  attr :active, :atom, required: true
  attr :id_prefix, :string, default: ""

  def render_tabs(assigns) do
    assigns = assign(assigns, :tabs, DelivestWeb.StaffNav.data_system_entries())

    ~H"""
    <ul
      :if={@id_prefix == "sidebar-"}
      id="sidebar-staff-page-header-navigation"
      phx-hook="ActiveSectionNav"
    >
      <li :for={tab <- @tabs}>
        <.link
          id={"#{@id_prefix}logs-tab-#{tab.id}"}
          navigate={tab.path}
          class={@active == tab.id && "menu-active"}
          aria-current={@active == tab.id && "page"}
        >
          <.icon name={tab.icon} class="size-4" />
          {tab.label}
        </.link>
      </li>
    </ul>
    <div :if={@id_prefix == ""} role="tablist" class="tabs">
      <.link
        :for={tab <- @tabs}
        id={"#{@id_prefix}logs-tab-#{tab.id}"}
        navigate={tab.path}
        role="tab"
        class={["tab gap-2 whitespace-nowrap", @active == tab.id && "tab-active font-bold"]}
        aria-current={@active == tab.id && "page"}
      >
        <.icon name={tab.icon} class="size-4" />
        {tab.label}
      </.link>
    </div>
    """
  end
end
