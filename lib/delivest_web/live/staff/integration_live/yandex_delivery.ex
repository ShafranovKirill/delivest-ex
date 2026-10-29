defmodule DelivestWeb.Staff.IntegrationLive.YandexDelivery do
  use DelivestWeb, :live_view

  alias Delivest.{Couriers, Identity}
  alias Delivest.Identity.Branch.CourierSettings
  alias Delivest.Integrations.YandexDelivery
  alias DelivestWeb.Staff.IntegrationLive.{HealthComponent, JournalComponent}

  on_mount {DelivestWeb.Hooks.Permission, "integrations.read"}

  @impl true
  def mount(_params, _session, socket) do
    branch_id = socket.assigns.current_branch.id

    {:ok,
     socket
     |> assign(
       page_title: gettext("Yandex Delivery"),
       can_edit: Identity.can?(socket.assigns.current_staff, "integrations.update"),
       couriers: Couriers.settings(branch_id),
       automatic: Couriers.automatic?(branch_id)
     )
     |> assign_settings(YandexDelivery.settings(branch_id))}
  end

  @impl true
  def handle_event("validate", %{"yandex_delivery" => params}, socket) do
    changeset =
      socket.assigns.settings
      |> YandexDelivery.change_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "yandex_delivery"))}
  end

  def handle_event("save", %{"yandex_delivery" => params}, socket) do
    case YandexDelivery.update_settings(
           socket.assigns.current_staff,
           socket.assigns.current_branch.id,
           params
         ) do
      {:ok, settings} ->
        {:noreply,
         socket |> assign_settings(settings) |> put_flash(:info, gettext("Settings saved"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket,
           form: to_form(Map.put(changeset, :action, :update), as: "yandex_delivery")
         )}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Please check the highlighted fields"))}
    end
  end

  defp assign_settings(socket, settings) do
    assign(socket,
      settings: settings,
      form: to_form(YandexDelivery.change_settings(settings), as: "yandex_delivery")
    )
  end

  defp taxi_class_options,
    do: [{gettext("Courier, up to 10 kg"), :courier}, {gettext("Express, up to 20 kg"), :express}]

  defp vat_options,
    do: [
      {gettext("No VAT"), :vat_none},
      {"0%", :vat0},
      {"10%", :vat10},
      {"20%", :vat20}
    ]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6 max-w-3xl">
      <.link
        navigate={~p"/staff/b/#{@current_branch}/integrations"}
        class="btn btn-ghost btn-sm -ml-2"
      >
        <.icon name="hero-arrow-left" class="size-4" /> {gettext("Integrations")}
      </.link>

      <.page_header
        title={gettext("Yandex Delivery")}
        subtitle={
          gettext(
            "A Yandex courier is called for the delivery orders of the branch. The search starts as set in the branch couriers."
          )
        }
      />

      <div
        :if={match?(%CourierSettings{source: :staff}, @couriers)}
        id="yandex-delivery-source"
        class="alert alert-warning text-sm"
      >
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>
          {gettext("The branch uses its own couriers. Choose Yandex Delivery in the branch couriers.")}
          <.link navigate={~p"/staff/b/#{@current_branch}/delivery/couriers"} class="link">
            {gettext("Branch couriers")}
          </.link>
        </span>
      </div>

      <div :if={not @automatic} id="yandex-delivery-crm" class="alert alert-info text-sm">
        <.icon name="hero-information-circle" class="size-5" />
        <span>
          {gettext(
            "The branch works through a CRM, the courier is not searched automatically. For orders that did not go to the CRM the operator calls a courier with the Find a courier button."
          )}
        </span>
      </div>

      <.live_component
        :if={YandexDelivery.Settings.configured?(@settings)}
        module={HealthComponent}
        id="yandex-delivery-health"
        provider={:yandex_delivery}
        branch_id={@current_branch.id}
        scope={@current_branch.id}
      />

      <.form
        for={@form}
        id="yandex-delivery-settings"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <.input
          field={@form[:token]}
          type="password"
          value=""
          label={gettext("OAuth token")}
          placeholder={if @settings.token, do: gettext("Saved, enter a new one to replace it")}
          disabled={not @can_edit}
        />
        <p class="-mt-2 text-xs text-base-content/60">
          {gettext("Personal account dostavka.yandex.ru, the Integrations tab.")}
        </p>

        <div class="grid gap-4 sm:grid-cols-2">
          <.input
            field={@form[:contact_name]}
            type="text"
            label={gettext("Contact at the branch")}
            placeholder={@current_branch.name}
            disabled={not @can_edit}
          />
          <.input
            field={@form[:contact_phone]}
            type="tel"
            label={gettext("Phone")}
            placeholder={gettext("Branch phone")}
            disabled={not @can_edit}
          />
          <.input
            field={@form[:contact_email]}
            type="email"
            label={gettext("Email")}
            disabled={not @can_edit}
          />
          <.input
            field={@form[:taxi_class]}
            type="select"
            label={gettext("Tariff")}
            options={taxi_class_options()}
            disabled={not @can_edit}
          />
          <.input
            field={@form[:vat]}
            type="select"
            label={gettext("VAT for the payment to the courier")}
            options={vat_options()}
            disabled={not @can_edit}
          />
        </div>

        <.input
          field={@form[:confirm_codes]}
          type="checkbox"
          label={gettext("Confirm the pickup and the handover with SMS codes")}
          disabled={not @can_edit}
        />

        <.input
          field={@form[:auto_accept]}
          type="checkbox"
          label={gettext("Confirm the claim automatically")}
          disabled={not @can_edit}
        />
        <p class="-mt-2 text-xs text-base-content/60">
          {gettext(
            "Only if the Yandex manager has enabled auto accept for your contract, otherwise claims are not created. Without it the claim is confirmed by the next poll within 10 seconds."
          )}
        </p>

        <p class="text-xs text-base-content/60">
          {gettext(
            "A Yandex courier takes payment by card only. A cash order switches to card to the courier when the courier is called."
          )}
        </p>

        <div :if={@can_edit} class="flex justify-end">
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>

      <.live_component
        module={JournalComponent}
        id="yandex-delivery-journal"
        provider={:yandex_delivery}
        branch_id={@current_branch.id}
      />
    </div>
    """
  end
end
