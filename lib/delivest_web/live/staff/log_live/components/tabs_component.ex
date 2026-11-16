defmodule DelivestWeb.Staff.LogLive.Components.TabsComponent do
  use DelivestWeb, :html

  attr :active, :atom, required: true
  attr :staff, :any, required: true
  attr :scope_branch, :any, default: nil
  attr :events_path, :string, default: nil

  def render_tabs(assigns) do
    transfer =
      assigns.staff
      |> DelivestWeb.StaffNav.settings_entries(assigns.scope_branch)
      |> Enum.find(&(&1.id == :data_transfer))

    entries =
      if(Delivest.Identity.can?(assigns.staff, "logs.read"),
        do: DelivestWeb.StaffNav.data_system_entries(),
        else: []
      )

    tabs =
      case {entries, transfer} do
        {[%{id: :events} = events | other], transfer} when not is_nil(transfer) ->
          [events, transfer | other]

        {entries, transfer} when not is_nil(transfer) ->
          [transfer | entries]

        {entries, nil} ->
          entries
      end

    assigns = assign(assigns, :tabs, tabs)

    ~H"""
    <nav
      id="data-system-navigation"
      phx-hook="ActiveSectionNav"
      aria-label={gettext("Data and system")}
      class="flex min-w-0 w-full flex-wrap gap-2"
    >
      <.link
        :for={tab <- @tabs}
        id={"data-system-action-#{tab.id}"}
        navigate={if(tab.id == :events and @events_path, do: @events_path, else: tab.path)}
        class={["btn btn-sm btn-ghost shrink-0 gap-2", @active == tab.id && "btn-active"]}
        aria-current={@active == tab.id && "page"}
      >
        <.icon name={tab.icon} class="size-4" />
        {tab.label}
      </.link>
    </nav>
    """
  end
end
