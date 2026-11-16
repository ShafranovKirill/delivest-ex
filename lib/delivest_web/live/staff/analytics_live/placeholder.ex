defmodule DelivestWeb.Staff.AnalyticsLive.Placeholder do
  use DelivestWeb, :live_view

  alias Delivest.Identity

  on_mount {DelivestWeb.Hooks.Permission, "statistics.read"}
  on_mount {DelivestWeb.Hooks.Permission, "statistics.network"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, attach_hook(socket, :analytics_permissions, :handle_info, &recheck_permissions/2)}
  end

  defp recheck_permissions(event, socket) when event in [:role_updated, :staff_updated] do
    staff = socket.assigns.current_staff

    if Identity.can?(staff, "statistics.read") and Identity.can?(staff, "statistics.network") do
      {:cont, socket}
    else
      {:halt,
       redirect(socket, to: DelivestWeb.StaffBranchPath.home(socket.assigns[:current_branch]))}
    end
  end

  defp recheck_permissions(_event, socket), do: {:cont, socket}

  @impl true
  def handle_params(%{"section" => section}, _uri, socket) do
    case title(section) do
      nil -> {:noreply, push_navigate(socket, to: ~p"/staff/statistics")}
      title -> {:noreply, assign(socket, page_title: title)}
    end
  end

  defp title("channels"), do: gettext("Sales channels")
  defp title("sources"), do: gettext("Sources")
  defp title("funnel"), do: gettext("Funnel")
  defp title("customers"), do: gettext("Buyers")
  defp title("comparison"), do: gettext("Branch comparison")
  defp title(_), do: nil

  def staff_page_header(assigns) do
    ~H"""
    <.page_header title={@page_title} />
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="analytics-placeholder" class="mx-auto max-w-3xl px-4 py-8 sm:px-6">
      <div class="rounded-2xl border border-base-300 bg-base-100 p-8 text-center shadow-sm">
        <p class="text-base-content/70">{gettext("Section under development")}</p>
      </div>
    </section>
    """
  end
end
