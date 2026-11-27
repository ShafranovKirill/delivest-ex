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
    <.page_header title={gettext("Integrations")} />
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <section class="space-y-3">
        <div>
          <h2 class="font-bold">{gettext("All branches")}</h2>
        </div>

        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <.integration_card
            :if={StaffAccess.allowed?(:yandex_ads)}
            id="integration-yandex-ads"
            title={gettext("Yandex Direct and Metrika")}
            state={
              %{
                configuration:
                  if(Delivest.Integrations.YandexAds.get_settings().enabled,
                    do: :enabled,
                    else: :disabled
                  )
              }
            }
            path={@can_edit_shared && ~p"/staff/integrations/yandex-ads"}
          />
          <.integration_card
            :if={Map.has_key?(@states, :zvonok)}
            id="integration-zvonok"
            title="Zvonok"
            state={@states[:zvonok]}
            path={@can_edit_shared && ~p"/staff/integrations/zvonok"}
          />
          <.integration_card
            :if={Map.has_key?(@states, :dadata)}
            id="integration-dadata"
            title="DaData"
            state={@states[:dadata]}
            path={@can_edit_shared && ~p"/staff/integrations/dadata"}
          />
          <.integration_card
            :if={Map.has_key?(@states, :yookassa)}
            id="integration-yookassa"
            title="ЮKassa"
            state={@states[:yookassa]}
            path={@can_edit_shared && ~p"/staff/integrations/yookassa"}
          />
          <.integration_card
            :if={Map.has_key?(@states, :yandex_eda)}
            id="integration-yandex-eda-shared"
            title="Яндекс Еда"
            state={@states[:yandex_eda]}
            path={@can_edit_shared && ~p"/staff/integrations/yandex-eda"}
          />
        </div>
      </section>

      <.link
        :if={@selected_branch && Identity.can?(@current_staff, "orders.update")}
        id="integration-recovery"
        navigate={~p"/staff/b/#{@selected_branch}/integrations/recovery"}
        class="btn btn-outline btn-sm"
      >
        {gettext("Review blocked deliveries")}
      </.link>

      <section :if={@selected_branch} class="space-y-3">
        <div>
          <h2 class="font-bold">{gettext("Branch settings")}</h2>
          <p id="integration-selected-branch" class="text-sm text-base-content/70">
            {gettext("Branch: %{name}", name: @selected_branch.name)}
          </p>
        </div>

        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <.integration_card
            :if={StaffAccess.allowed?(:vk_ads)}
            id="integration-vk-ads"
            title={gettext("VK Реклама / Top.Mail.Ru")}
            state={vk_ads_state(@selected_branch)}
            path={~p"/staff/b/#{@selected_branch}/integrations/vk-ads"}
          />
          <.integration_card
            :if={StaffAccess.allowed?(:ycart)}
            id="integration-ycart"
            title={gettext("YCart")}
            state={ycart_state(@selected_branch)}
            path={~p"/staff/b/#{@selected_branch}/integrations/ycart"}
          />
          <.integration_card
            id="integration-routes"
            title={gettext("Order routes")}
            state={@routes_state}
            path={~p"/staff/b/#{@selected_branch}/integrations/routes"}
          />
          <.integration_card
            :if={Map.has_key?(@states, :yandex_eda)}
            id="integration-yandex-eda"
            title="Яндекс Еда"
            state={@states[:yandex_eda]}
            path={~p"/staff/b/#{@selected_branch}/integrations/yandex-eda"}
          />
          <.integration_card
            :if={Map.has_key?(@states, :atol)}
            id="integration-fiscal"
            title="АТОЛ Онлайн"
            state={@states[:atol]}
            path={~p"/staff/b/#{@selected_branch}/integrations/fiscal"}
          />
          <.integration_card
            :if={Map.has_key?(@states, :yandex_delivery)}
            id="integration-yandex-delivery"
            title={gettext("Yandex Delivery")}
            state={@states[:yandex_delivery]}
            path={~p"/staff/b/#{@selected_branch}/integrations/yandex-delivery"}
          />
          <.integration_card
            :for={{provider, name} <- Crm.providers()}
            :if={Map.has_key?(@states, provider)}
            id={"integration-#{provider}"}
            title={name}
            state={@states[provider]}
            path={provider_path(@selected_branch, provider)}
          />
        </div>
      </section>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :state, :map, default: nil
  attr :path, :any, required: true

  defp integration_card(%{path: path} = assigns) when is_binary(path) do
    ~H"""
    <div class="rounded-box border border-base-300 bg-base-100">
      <.link
        id={@id}
        navigate={@path}
        class="block rounded-box hover:bg-base-200 focus-visible:outline-2 focus-visible:outline-primary"
      >
        <.integration_summary id={@id} title={@title} state={@state} />
      </.link>
    </div>
    """
  end

  defp integration_card(assigns) do
    ~H"""
    <div id={@id} class="rounded-box border border-base-300 bg-base-100">
      <.integration_summary id={@id} title={@title} state={@state} />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :state, :map, default: nil

  defp integration_summary(assigns) do
    assigns = assign(assigns, :connected?, integration_connected?(assigns.state))

    ~H"""
    <div class="flex min-h-20 flex-wrap items-center justify-between gap-3 p-4">
      <h3 class="text-base font-semibold">{@title}</h3>
      <.status_badge
        id={"#{@id}-state"}
        label={if @connected?, do: gettext("Connected"), else: gettext("Not connected")}
        tone={if @connected?, do: :success, else: :muted}
        class="badge-sm badge-soft rounded-full"
      />
    </div>
    """
  end

  defp integration_connected?(%{configuration: :enabled}), do: true

  defp integration_connected?(%{main: main})
       when main in [:enabled, :partial, :attention, :unchecked, :error],
       do: true

  defp integration_connected?(_state), do: false

  defp ycart_state(branch) do
    settings = branch.info && branch.info.ycart_settings
    %{configuration: if(settings && settings.enabled, do: :enabled, else: :disabled)}
  end

  defp vk_ads_state(branch) do
    config =
      Delivest.Identity.Branch.VkAdsSettings.public_config(branch.info && branch.info.vk_ads)

    %{configuration: if(config.enabled, do: :enabled, else: :disabled)}
  end
end
