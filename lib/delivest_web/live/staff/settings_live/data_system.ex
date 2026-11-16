defmodule DelivestWeb.Staff.SettingsLive.DataSystem do
  use DelivestWeb, :live_view

  alias DelivestWeb.Staff.LogLive.Components.TabsComponent

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff

    if Enum.any?(DelivestWeb.StaffNav.settings_entries(staff, nil), &(&1.id == :data_system)) do
      {:ok, assign(socket, page_title: gettext("Data and system"))}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Permission denied"))
       |> redirect(to: ~p"/staff/dashboard")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    branch = Enum.find(socket.assigns.staff_branches, &(&1.slug == params["branch"]))

    if params["branch"] && is_nil(branch) do
      {:noreply,
       socket
       |> put_flash(:error, gettext("Permission denied"))
       |> push_navigate(to: ~p"/staff/settings/data-system")}
    else
      {:noreply, assign(socket, settings_scope_branch: branch)}
    end
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header title={gettext("Data and system")} />
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="data-system-content">
      <TabsComponent.render_tabs
        active={nil}
        staff={@current_staff}
        scope_branch={@settings_scope_branch}
      />
    </div>
    """
  end
end
