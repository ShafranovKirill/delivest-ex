defmodule DelivestWeb.Staff.MarketingLive.Hub do
  use DelivestWeb, :live_view

  alias Delivest.{Features, Identity}
  alias DelivestWeb.Staff.MarketingLive.Navigation

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff

    if Navigation.available?(staff, socket.assigns.staff_branches) do
      {:ok,
       assign(socket,
         page_title: gettext("Marketing"),
         current_branch: nil
       )}
    else
      {:ok, redirect(socket, to: ~p"/staff/branches/select")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    branch = Enum.find(socket.assigns.staff_branches, &(&1.slug == params["branch"]))

    section =
      case params["section"] do
        "stocks" -> :stocks
        "promotions" -> :promotions
        "loyalty" -> :loyalty
        "links" -> :links
        _ -> :hub
      end

    {:noreply, assign(socket, current_branch: branch, section: section)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="marketing-hub" class="space-y-6">
      <.page_header
        title={gettext("Marketing")}
        subtitle={gettext("Choose a marketing area and branch.")}
      />
      <Navigation.navigation
        staff={@current_staff}
        branches={@staff_branches}
        branch={@current_branch}
        active={@section}
      />
      <section class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <.link
          :if={
            Identity.can?(@current_staff, "marketing.read") and
              Features.enabled?("marketing_policies", :franchise)
          }
          id="marketing-policies-link"
          navigate={~p"/staff/marketing/policies"}
          class="card border border-base-300 bg-base-100 p-5 hover:border-primary"
        >
          <h2 class="font-semibold">{gettext("Marketing policies")}</h2>
          <p class="text-sm text-base-content/60">
            {gettext("Rewards and customer segments across the franchise.")}
          </p>
        </.link>
        <.link
          :if={
            Identity.can?(@current_staff, "segments.read") and
              Delivest.Segments.available?(@current_staff)
          }
          id="marketing-segments-link"
          navigate={~p"/staff/segments"}
          class="card border border-base-300 bg-base-100 p-5 hover:border-primary"
        >
          <h2 class="font-semibold">{gettext("Segments")}</h2>
        </.link>
      </section>
    </div>
    """
  end
end
