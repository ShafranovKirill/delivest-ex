defmodule DelivestWeb.Staff.MarketingLive.Bonuses do
  use DelivestWeb, :live_view

  alias Delivest.{Gateway, Identity}
  alias DelivestWeb.Staff.MarketingLive.Navigation

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff

    branches =
      socket.assigns.staff_branches
      |> Delivest.Repo.preload(:info)
      |> Enum.filter(fn branch ->
        Identity.authorize(staff, "promotions.read", branch.id) == :ok and
          Gateway.own?(branch, :loyalty)
      end)

    if Identity.can?(staff, "franchise.update") or branches != [] do
      {:ok,
       socket
       |> assign(page_title: gettext("Bonuses"), current_branch: nil, bonus_branches: branches)}
    else
      {:ok, redirect(socket, to: ~p"/staff/branches/select")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="bonuses-page" class="space-y-6">
      <.page_header
        title={gettext("Bonuses")}
        subtitle={gettext("Common bonus rules and branch settings.")}
      />

      <Navigation.navigation
        staff={@current_staff}
        branches={@staff_branches}
        branch={nil}
        active={:loyalty}
      />

      <.live_component
        module={DelivestWeb.Staff.MarketingLive.BonusSettingsComponent}
        id="global-bonuses"
        current_staff={@current_staff}
      />

      <section id="branch-bonuses" class="space-y-3">
        <h2 class="text-lg font-semibold">{gettext("Branch bonus settings")}</h2>
        <p class="text-sm text-base-content/60">
          {gettext("Choose an available branch to manage its bonus program and reward products.")}
        </p>
        <div class="grid gap-3 sm:grid-cols-2">
          <.link
            :for={branch <- @bonus_branches}
            id={"bonus-branch-#{branch.id}"}
            navigate={~p"/staff/b/#{branch}/loyalty"}
            class="card border border-base-300 bg-base-100 p-4 hover:border-primary"
          >{branch.name}</.link>
        </div>
        <p :if={@bonus_branches == []} class="text-sm text-base-content/60">
          {gettext("No branches available")}
        </p>
      </section>
    </div>
    """
  end
end
