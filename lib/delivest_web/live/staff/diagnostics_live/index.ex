defmodule DelivestWeb.Staff.DiagnosticsLive.Index do
  use DelivestWeb, :live_view

  alias DelivestWeb.Staff.LogLive.Components.TabsComponent

  on_mount {DelivestWeb.Hooks.Permission, "logs.read"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: gettext("Metrics"))}
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header title={gettext("Metrics")} />
    """
  end

  def staff_page_navigation(assigns) do
    ~H"""
    <nav
      :if={@navigation_id_prefix == ""}
      id="staff-page-header-navigation"
      phx-hook="ActiveSectionNav"
      aria-label={gettext("Data and system")}
      class="flex gap-1 overflow-x-auto whitespace-nowrap px-4 py-2 sm:px-6"
    >
      <TabsComponent.render_tabs active={:metrics} />
    </nav>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <iframe
      id="staff-metrics-frame"
      title={gettext("Metrics")}
      src={~p"/staff/metrics"}
      class="h-[calc(100dvh-var(--staff-header-height)-3rem)] min-h-[32rem] w-full bg-base-100"
    />
    """
  end
end
