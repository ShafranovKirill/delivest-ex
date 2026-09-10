defmodule DelivestWeb.Staff.DashboardLive.Index do
  use DelivestWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  @spec render(any()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex-1 flex flex-col items-center justify-center p-4">
      <div class="w-full flex flex-col max-w-md items-center">
        <h2 class="text-2xl font-display font-bold uppercase">
          {gettext("Dashboard")}
        </h2>
        <.link href={~p"/staff/auth/log_out"} method="delete" class="btn btn-primary w-auto mt-5">
          {gettext("Log out")}
          <.icon name="hero-arrow-right-end-on-rectangle" />
        </.link>
      </div>
    </div>
    """
  end
end
