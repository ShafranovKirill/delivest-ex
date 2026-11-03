defmodule DelivestWeb.Staff.IntegrationLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.BranchSettings
  alias DelivestWeb.Staff.IntegrationLive.Presentation

  on_mount {DelivestWeb.Hooks.Permission, "integrations.read"}

  @providers [:zvonok, :dadata, :yookassa, :yandex_eda, :atol, :yandex_delivery]

  @impl true
  def mount(_params, _session, socket) do
    context = Presentation.context(socket.assigns.current_branch.id)

    providers = @providers ++ Enum.map(Crm.providers(), &elem(&1, 0))
    states = Map.new(providers, &{&1, Presentation.state(&1, context)})

    {:ok,
     assign(socket,
       page_title: gettext("Integrations"),
       states: states,
       routes_state: routes_state(context),
       can_edit_shared: Identity.can?(socket.assigns.current_staff, "admin")
     )}
  end

  defp routes_state(context) do
    case BranchSettings.active_provider(context.crm) do
      nil -> nil
      provider -> Presentation.state(provider, context)
    end
  end

  defp provider_path(branch, :frontpad), do: ~p"/staff/b/#{branch}/integrations/frontpad"
  defp provider_path(branch, :iiko), do: ~p"/staff/b/#{branch}/integrations/iiko"
  defp provider_path(branch, :rkeeper), do: ~p"/staff/b/#{branch}/integrations/rkeeper"
  defp provider_path(branch, _provider), do: ~p"/staff/b/#{branch}/integrations"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8 py-4 sm:p-6">
      <.page_header
        title={gettext("Integrations")}
        subtitle={gettext("External services connected to the app.")}
      />

      <section class="space-y-3">
        <div>
          <h2 class="font-bold">{gettext("All branches")}</h2>
          <p class="text-sm text-base-content/60">
            {gettext("These settings are shared by every branch.")}
          </p>
        </div>

        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <.integration_card
            id="integration-zvonok"
            title={gettext("Sign-in by phone number")}
            description={gettext("Customers confirm the phone number with a call via zvonok.com.")}
            state={@states[:zvonok]}
            branch={@current_branch}
            path={@can_edit_shared && ~p"/staff/b/#{@current_branch}/integrations/zvonok"}
          />
          <.integration_card
            id="integration-dadata"
            title={gettext("Delivery address on the map")}
            description={gettext("Address suggestions and the map via dadata.ru.")}
            state={@states[:dadata]}
            branch={@current_branch}
            path={@can_edit_shared && ~p"/staff/b/#{@current_branch}/integrations/dadata"}
          />
          <.integration_card
            id="integration-yookassa"
            title={gettext("Online payment")}
            description={gettext("Card and SBP payments through YooKassa.")}
            state={@states[:yookassa]}
            branch={@current_branch}
            path={@can_edit_shared && ~p"/staff/b/#{@current_branch}/integrations/yookassa"}
          />
        </div>
      </section>

      <DelivestWeb.GatewayNote.gateway_summary branch={@current_branch} />

      <section class="space-y-3">
        <div>
          <h2 class="font-bold">{gettext("Branch")} «{@current_branch.name}»</h2>
          <p class="text-sm text-base-content/60">
            {gettext("Each branch has its own settings. Switch the branch to set up another one.")}
          </p>
        </div>

        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <.integration_card
            id="integration-routes"
            title={gettext("Order routes")}
            description={gettext("Which orders go further to the CRM.")}
            state={@routes_state}
            branch={@current_branch}
            path={~p"/staff/b/#{@current_branch}/integrations/routes"}
          />
          <.integration_card
            id="integration-yandex-eda"
            title={gettext("Yandex Eda")}
            description={gettext("Orders from Yandex Eda and Delivery Club.")}
            state={@states[:yandex_eda]}
            branch={@current_branch}
            path={~p"/staff/b/#{@current_branch}/integrations/yandex-eda"}
          />
          <.integration_card
            id="integration-fiscal"
            title={gettext("Receipts")}
            description={gettext("Fiscal receipts through ATOL Online.")}
            state={@states[:atol]}
            branch={@current_branch}
            path={~p"/staff/b/#{@current_branch}/integrations/fiscal"}
          />
          <.integration_card
            id="integration-yandex-delivery"
            title={gettext("Yandex Delivery")}
            description={gettext("A Yandex courier for the delivery orders.")}
            state={@states[:yandex_delivery]}
            branch={@current_branch}
            path={~p"/staff/b/#{@current_branch}/integrations/yandex-delivery"}
          />
          <.integration_card
            :for={{provider, name} <- Crm.providers()}
            id={"integration-#{provider}"}
            title={name}
            description={gettext("Orders to the CRM and products matching with the app menu.")}
            state={@states[provider]}
            branch={@current_branch}
            path={provider_path(@current_branch, provider)}
          />
        </div>
      </section>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :state, :map, default: nil
  attr :branch, :any, required: true
  attr :path, :any, required: true

  defp integration_card(%{path: path} = assigns) when is_binary(path) do
    ~H"""
    <.link
      id={@id}
      navigate={@path}
      class="card bg-base-100 border border-base-300 hover:border-primary transition-colors"
    >
      <.card_body
        id={@id}
        title={@title}
        description={@description}
        state={@state}
        branch={@branch}
      />
    </.link>
    """
  end

  defp integration_card(assigns) do
    ~H"""
    <div id={@id} class="card bg-base-100 border border-base-300">
      <.card_body
        id={@id}
        title={@title}
        description={@description}
        state={@state}
        branch={@branch}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :state, :map, default: nil
  attr :branch, :any, required: true

  defp card_body(assigns) do
    ~H"""
    <div class="card-body gap-2">
      <h3 class="card-title text-base">{@title}</h3>
      <p class="text-sm text-base-content/60">{@description}</p>
      <.compact_state :if={@state} id={"#{@id}-state"} state={@state} />
      <p :if={is_nil(@state)} class="text-sm text-base-content/50">
        {gettext("No CRM is connected to this branch.")}
      </p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :state, :map, required: true

  defp compact_state(assigns) do
    ~H"""
    <div id={@id} class="flex items-center gap-2 text-sm">
      <.status_badge state={overall_status(@state)} />
    </div>
    """
  end

  defp overall_status(%{connection: %{state: :ok}, warnings: warnings}) do
    if warnings != [] and Enum.any?(warnings), do: :attention, else: :ok
  end

  defp overall_status(%{connection: %{state: :ok}}), do: :ok

  defp overall_status(%{connection: %{state: :auth}}), do: :auth
  defp overall_status(%{connection: %{state: :failed}}), do: :failed
  defp overall_status(%{connection: %{state: :unchecked}, credentials: %{state: cred}}) do
    case cred do
      :complete -> :unchecked
      _ -> :needs_setup
    end
  end

  defp overall_status(_state), do: :needs_setup

  defp status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium",
      @status == :ok && "bg-success/10 text-success",
      @status == :attention && "bg-warning/10 text-warning",
      @status == :auth && "bg-error/10 text-error",
      @status == :failed && "bg-error/10 text-error",
      @status == :unchecked && "bg-base-300/50 text-base-content/60",
      @status == :needs_setup && "bg-base-300/50 text-base-content/50"
    ]}>
      <span class={[
        "size-1.5 rounded-full",
        @status == :ok && "bg-success",
        @status == :attention && "bg-warning",
        @status == :auth && "bg-error",
        @status == :failed && "bg-error",
        @status == :unchecked && "bg-base-content/30",
        @status == :needs_setup && "bg-base-content/20"
      ]} />
      {status_text(@status)}
    </span>
    """
  end

  defp status_text(:ok), do: gettext("OK")
  defp status_text(:attention), do: gettext("Needs attention")
  defp status_text(:auth), do: gettext("Access error")
  defp status_text(:failed), do: gettext("No connection")
  defp status_text(:unchecked), do: gettext("Not checked")
  defp status_text(:needs_setup), do: gettext("Not set up")
end
