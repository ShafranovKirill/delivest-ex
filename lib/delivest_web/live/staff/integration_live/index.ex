defmodule DelivestWeb.Staff.IntegrationLive.Index do
  use DelivestWeb, :live_view

  import DelivestWeb.Staff.FoundationComponents, only: [status_badge: 1]

  alias Delivest.Identity
  alias Delivest.Integrations.{Crm, StaffAccess}
  alias Delivest.Integrations.Crm.BranchSettings
  alias DelivestWeb.Staff.IntegrationLive.Presentation

  on_mount {DelivestWeb.Hooks.Permission, "integrations.read"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Integrations"),
       can_edit_shared: Identity.can?(socket.assigns.current_staff, "admin")
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    branches = Identity.list_branch_for_staff(socket.assigns.current_staff)

    branch =
      case params do
        %{"branch_slug" => slug} -> Enum.find(branches, &(&1.slug == slug))
        %{"branch" => slug} -> Enum.find(branches, &(&1.slug == slug))
        _ -> nil
      end

    if params["branch"] && is_nil(branch) do
      {:noreply,
       socket
       |> put_flash(:error, gettext("Permission denied"))
       |> push_patch(to: ~p"/staff/integrations")}
    else
      assign_summary(socket, branches, branch)
    end
  end

  defp assign_summary(socket, _branches, branch) do
    context = Presentation.context(branch && branch.id)

    providers = Presentation.providers(branch)

    {:noreply,
     assign(socket,
       selected_branch: context.branch,
       states:
         providers
         |> Enum.filter(&StaffAccess.allowed?/1)
         |> Map.new(&{&1, Presentation.state(&1, context)}),
       routes_state: if(branch, do: routes_state(context), else: nil)
     )}
  end

  defp routes_state(context) do
    case BranchSettings.active_provider(context.crm) do
      nil -> nil
      provider -> if StaffAccess.allowed?(provider), do: Presentation.state(provider, context)
    end
  end

  defp provider_path(branch, :frontpad), do: ~p"/staff/b/#{branch}/integrations/frontpad"
  defp provider_path(branch, :iiko), do: ~p"/staff/b/#{branch}/integrations/iiko"
  defp provider_path(branch, :rkeeper), do: ~p"/staff/b/#{branch}/integrations/rkeeper"
  defp provider_path(branch, _provider), do: ~p"/staff/b/#{branch}/integrations"

  def staff_page_header(assigns) do
    ~H"""
    <.page_header
      title={gettext("Integrations")}
      subtitle={gettext("External services connected to the app.")}
    />
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <section class="space-y-3">
        <div>
          <h2 class="font-bold">{gettext("All branches")}</h2>
          <p class="text-sm text-base-content/60">
            {gettext("These settings are shared by every branch.")}
          </p>
        </div>

        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <.integration_card
            :if={StaffAccess.allowed?(:yandex_ads)}
            id="integration-yandex-ads"
            title={gettext("Yandex Direct and Metrika")}
            description={gettext("Visits, product feeds, completed orders and advertising costs.")}
            state={
              %{
                configuration:
                  if(Delivest.Integrations.YandexAds.get_settings().enabled,
                    do: :enabled,
                    else: :disabled
                  )
              }
            }
            branch={@selected_branch}
            path={@can_edit_shared && ~p"/staff/integrations/yandex-ads"}
          />
          <.integration_card
            :if={Map.has_key?(@states, :zvonok)}
            id="integration-zvonok"
            title={gettext("Sign-in by phone number")}
            description={gettext("Customers confirm the phone number with a call via zvonok.com.")}
            state={@states[:zvonok]}
            branch={@selected_branch}
            path={@can_edit_shared && ~p"/staff/integrations/zvonok"}
          />
          <.integration_card
            :if={Map.has_key?(@states, :dadata)}
            id="integration-dadata"
            title={gettext("Delivery address on the map")}
            description={gettext("Address suggestions and the map via dadata.ru.")}
            state={@states[:dadata]}
            branch={@selected_branch}
            path={@can_edit_shared && ~p"/staff/integrations/dadata"}
          />
          <.integration_card
            :if={Map.has_key?(@states, :yookassa)}
            id="integration-yookassa"
            title={gettext("Online payment")}
            description={gettext("Card and SBP payments through YooKassa.")}
            state={@states[:yookassa]}
            branch={@selected_branch}
            path={@can_edit_shared && ~p"/staff/integrations/yookassa"}
          />
          <.integration_card
            :if={Map.has_key?(@states, :yandex_eda)}
            id="integration-yandex-eda-shared"
            title={gettext("Yandex Eda access")}
            description={gettext("Access credentials shared by every branch.")}
            state={@states[:yandex_eda]}
            branch={@selected_branch}
            path={@can_edit_shared && ~p"/staff/integrations/yandex-eda"}
          />
        </div>
      </section>

      <DelivestWeb.GatewayNote.gateway_summary :if={@selected_branch} branch={@selected_branch} />

      <.link
        :if={@selected_branch && Identity.can?(@current_staff, "orders.update")}
        id="integration-recovery"
        navigate={~p"/staff/b/#{@selected_branch}/integrations/recovery"}
        class="btn btn-outline btn-sm"
      >
        {gettext("Review blocked deliveries")}
      </.link>

      <section class="space-y-3">
        <div>
          <h2 class="font-bold">{gettext("Branch settings")}</h2>
          <p class="text-sm text-base-content/60">
            {gettext("Choose a branch to view and change its integrations.")}
          </p>
        </div>

        <p :if={@selected_branch} id="integration-selected-branch" class="text-sm font-medium">
          {gettext("Branch: %{name}", name: @selected_branch.name)}
        </p>

        <div :if={@selected_branch} class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <.integration_card
            :if={StaffAccess.allowed?(:vk_ads)}
            id="integration-vk-ads"
            title={gettext("VK Реклама / Top.Mail.Ru")}
            description={gettext("Просмотры страниц публичной витрины выбранного филиала.")}
            state={vk_ads_state(@selected_branch)}
            branch={@selected_branch}
            path={~p"/staff/b/#{@selected_branch}/integrations/vk-ads"}
          />
          <.integration_card
            :if={StaffAccess.allowed?(:ycart)}
            id="integration-ycart"
            title={gettext("YCart")}
            description={gettext("Branch map and organization link on Yandex Maps.")}
            state={ycart_state(@selected_branch)}
            branch={@selected_branch}
            path={~p"/staff/b/#{@selected_branch}/integrations/ycart"}
          />
          <.integration_card
            id="integration-routes"
            title={gettext("Order routes")}
            description={gettext("Which orders go further to the CRM.")}
            state={@routes_state}
            branch={@selected_branch}
            path={~p"/staff/b/#{@selected_branch}/integrations/routes"}
          />
          <.integration_card
            :if={Map.has_key?(@states, :yandex_eda)}
            id="integration-yandex-eda"
            title={gettext("Yandex Eda")}
            description={gettext("Orders from Yandex Eda and Delivery Club.")}
            state={@states[:yandex_eda]}
            branch={@selected_branch}
            path={~p"/staff/b/#{@selected_branch}/integrations/yandex-eda"}
          />
          <.integration_card
            :if={Map.has_key?(@states, :atol)}
            id="integration-fiscal"
            title={gettext("Receipts")}
            description={gettext("Fiscal receipts through ATOL Online.")}
            state={@states[:atol]}
            branch={@selected_branch}
            path={~p"/staff/b/#{@selected_branch}/integrations/fiscal"}
          />
          <.integration_card
            :if={Map.has_key?(@states, :yandex_delivery)}
            id="integration-yandex-delivery"
            title={gettext("Yandex Delivery")}
            description={gettext("A Yandex courier for the delivery orders.")}
            state={@states[:yandex_delivery]}
            branch={@selected_branch}
            path={~p"/staff/b/#{@selected_branch}/integrations/yandex-delivery"}
          />
          <.integration_card
            :for={{provider, name} <- Crm.providers()}
            :if={Map.has_key?(@states, provider)}
            id={"integration-#{provider}"}
            title={name}
            description={gettext("Orders to the CRM and products matching with the app menu.")}
            state={@states[provider]}
            branch={@selected_branch}
            path={provider_path(@selected_branch, provider)}
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
    <div class="card border border-base-300 bg-base-100">
      <.link id={@id} navigate={@path} class="rounded-t-box hover:bg-base-200">
        <.card_body
          id={@id}
          title={@title}
          description={@description}
          state={@state}
          branch={@branch}
        />
      </.link>
      <.connection_details id={@id} state={@state} branch={@branch} />
    </div>
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
      <.connection_details id={@id} state={@state} branch={@branch} />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :state, :map, default: nil
  attr :branch, :any, required: true

  defp connection_details(assigns) do
    ~H"""
    <details
      :if={
        @state && Map.has_key?(@state, :credentials) &&
          Map.has_key?(@state, :connection) && Map.has_key?(@state, :usage)
      }
      id={"#{@id}-details"}
      class="border-t border-base-300 px-6 py-3 text-sm"
    >
      <summary class="cursor-pointer font-medium text-primary">
        {gettext("Connection details")}
      </summary>
      <div class="mt-3 space-y-2">
        <DelivestWeb.Staff.IntegrationLive.StateComponents.credentials_row
          id={"#{@id}-credentials"}
          credentials={@state.credentials}
        />
        <DelivestWeb.Staff.IntegrationLive.StateComponents.connection_row
          id={"#{@id}-connection"}
          connection={@state.connection}
          branch={@branch}
        />
        <DelivestWeb.Staff.IntegrationLive.StateComponents.usage_rows
          id={"#{@id}-usage"}
          usage={@state.usage}
        />
      </div>
    </details>
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
    assigns = assign(assigns, :status, overall_status(assigns.state))

    ~H"""
    <div id={@id} class="flex items-center gap-2 text-sm">
      <.status_badge
        id={"#{@id}-badge"}
        label={status_text(@status)}
        tone={status_tone(@status)}
        class="badge-sm badge-soft rounded-full"
      />
    </div>
    """
  end

  defp overall_status(%{main: main}), do: main
  defp overall_status(%{configuration: :enabled}), do: :enabled
  defp overall_status(%{configuration: :disabled}), do: :disabled

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

  defp ycart_state(branch) do
    settings = branch.info && branch.info.ycart_settings
    %{configuration: if(settings && settings.enabled, do: :enabled, else: :disabled)}
  end

  defp vk_ads_state(branch) do
    config =
      Delivest.Identity.Branch.VkAdsSettings.public_config(branch.info && branch.info.vk_ads)

    %{configuration: if(config.enabled, do: :enabled, else: :disabled)}
  end

  defp status_tone(status) when status in [:ok, :enabled], do: :success
  defp status_tone(status) when status in [:attention, :partial, :finishing], do: :warning
  defp status_tone(status) when status in [:error, :auth, :failed], do: :error
  defp status_tone(_status), do: :muted

  defp status_text(:enabled), do: gettext("Enabled")
  defp status_text(:partial), do: gettext("Partially enabled")
  defp status_text(:error), do: gettext("Error")
  defp status_text(:finishing), do: gettext("Completing orders")
  defp status_text(:disabled), do: gettext("Disabled")
  defp status_text(:ok), do: gettext("OK")
  defp status_text(:attention), do: gettext("Needs attention")
  defp status_text(:auth), do: gettext("Access error")
  defp status_text(:failed), do: gettext("No connection")
  defp status_text(:unchecked), do: gettext("Not checked")
  defp status_text(:needs_setup), do: gettext("Not set up")
end
