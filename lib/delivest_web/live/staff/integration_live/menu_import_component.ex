defmodule DelivestWeb.Staff.IntegrationLive.MenuImportComponent do
  use DelivestWeb, :live_component

  alias Delivest.Integrations.Crm
  alias Delivest.Net.MenuImport

  @impl true
  def mount(socket), do: {:ok, assign(socket, menu: nil, plan: nil, provider: nil, error: nil)}

  @impl true
  def handle_event("check", _params, socket) do
    case Crm.fetch_menu(socket.assigns.branch_id) do
      {:ok, provider, menu} ->
        {:noreply,
         assign(socket,
           provider: provider,
           menu: menu,
           plan: MenuImport.diff(socket.assigns.branch_id, provider, menu),
           error: nil
         )}

      {:error, reason} ->
        {:noreply, assign(socket, error: inspect(reason), plan: nil)}
    end
  end

  def handle_event("apply", _params, %{assigns: %{menu: menu}} = socket) when not is_nil(menu) do
    %{staff: staff, branch_id: branch_id, provider: provider} = socket.assigns

    case MenuImport.apply(staff, branch_id, provider, menu) do
      {:ok, summary} ->
        {:noreply,
         socket
         |> assign(menu: nil, plan: nil)
         |> put_flash(
           :info,
           gettext("Menu updated: %{added} added, %{changed} changed, %{hidden} hidden",
             added: summary.added,
             changed: summary.changed,
             hidden: summary.hidden
           )
         )}

      {:error, reason} ->
        {:noreply, assign(socket, error: inspect(reason))}
    end
  end

  def handle_event("apply", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5">
      <p class="text-sm text-base-content/70">
        {gettext(
          "Products, prices, sizes and modifiers come from the CRM. Photos, descriptions and tags stay ours. Products removed in the CRM are hidden."
        )}
      </p>
      <div class="flex gap-2">
        <button
          id={"#{@id}-check"}
          type="button"
          phx-click="check"
          phx-target={@myself}
          phx-disable-with={gettext("Loading...")}
          class="btn"
        >
          <.icon name="hero-arrow-path" class="size-4" /> {gettext("Check the menu")}
        </button>
        <button
          :if={@plan && @can_edit}
          id={"#{@id}-apply"}
          type="button"
          phx-click="apply"
          phx-target={@myself}
          phx-disable-with={gettext("Saving...")}
          data-confirm={gettext("Apply the menu from the CRM?")}
          class="btn btn-primary"
        >
          {gettext("Apply")}
        </button>
      </div>
      <p :if={@error} class="text-error">{@error}</p>

      <div :if={@plan} id={"#{@id}-plan"} class="grid gap-4 sm:grid-cols-3">
        <.plan_list title={gettext("Will be added")} names={Enum.map(@plan.added, & &1.name)} />
        <.plan_list
          title={gettext("Will be changed")}
          names={Enum.map(@plan.changed, & &1.product.name)}
        />
        <.plan_list title={gettext("Will be hidden")} names={Enum.map(@plan.hidden, & &1.name)} />
      </div>
    </section>
    """
  end

  attr :title, :string, required: true
  attr :names, :list, required: true

  defp plan_list(assigns) do
    ~H"""
    <div>
      <p class="font-bold">{@title} <span class="badge badge-sm">{length(@names)}</span></p>
      <ul class="mt-1 max-h-64 overflow-y-auto text-sm text-base-content/70">
        <li :for={name <- @names}>{name}</li>
      </ul>
    </div>
    """
  end
end
