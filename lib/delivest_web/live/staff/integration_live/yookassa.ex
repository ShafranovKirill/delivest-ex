defmodule DelivestWeb.Staff.IntegrationLive.Yookassa do
  use DelivestWeb, :live_view

  alias Delivest.Integrations.Yookassa
  alias DelivestWeb.Staff.IntegrationLive.JournalComponent

  on_mount {DelivestWeb.Hooks.Permission, "admin"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Online payment"), shop: nil)
     |> assign_settings(Yookassa.get_settings())}
  end

  @impl true
  def handle_event("validate", %{"yookassa" => params}, socket) do
    changeset =
      socket.assigns.settings
      |> Yookassa.change_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "yookassa"))}
  end

  def handle_event("save", %{"yookassa" => params}, socket) do
    case Yookassa.update_settings(socket.assigns.current_staff, params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign_settings(settings)
         |> assign(shop: nil)
         |> put_flash(:info, gettext("Settings saved"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "yookassa"))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  def handle_event("check", _params, socket) do
    shop =
      case Yookassa.shop(socket.assigns.settings) do
        {:ok, shop} -> shop
        {:error, _reason} -> :error
      end

    {:noreply, assign(socket, shop: shop)}
  end

  defp assign_settings(socket, settings) do
    assign(socket,
      settings: settings,
      form: to_form(Yookassa.change_settings(settings), as: "yookassa")
    )
  end

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
        title={gettext("Online payment")}
        subtitle={
          gettext("Card and SBP payments through YooKassa. The shop is shared by every branch.")
        }
      />

      <.form
        for={@form}
        id="yookassa-settings"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <div class="grid gap-4 sm:grid-cols-2">
          <.input field={@form[:shop_id]} type="text" label={gettext("Shop ID")} />
          <div class="space-y-1">
            <.input
              field={@form[:secret_key]}
              type="password"
              value={nil}
              label={gettext("Secret key")}
              placeholder={@settings.secret_key && "••••••••"}
            />
            <p :if={@settings.secret_key} class="text-xs text-base-content/60">
              {gettext("Leave empty to keep the saved key.")}
            </p>
          </div>
        </div>

        <div class="flex justify-end gap-2">
          <button
            :if={@settings.id}
            type="button"
            id="yookassa-check"
            class="btn btn-ghost"
            phx-click="check"
          >
            {gettext("Check connection")}
          </button>
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>

      <section
        :if={@shop}
        id="yookassa-shop"
        class="space-y-2 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <p :if={@shop == :error} id="yookassa-shop-error" class="text-error">
          {gettext("YooKassa did not accept the shop ID and the key.")}
        </p>

        <div :if={is_map(@shop)} class="space-y-2">
          <p>
            {gettext("Shop %{id}", id: @shop.account_id)}
            <span :if={@shop.test} class="badge badge-warning badge-sm">{gettext("test")}</span>
            <span :if={!@shop.enabled} class="badge badge-error badge-sm">
              {gettext("not connected")}
            </span>
          </p>
          <p
            :if={@shop.receipts_conflict}
            id="yookassa-receipts-conflict"
            class="rounded-box bg-warning/15 px-3 py-2 text-sm"
          >
            {gettext(
              "Receipts are turned on in the YooKassa shop (%{provider}). They are printed by our own cash desk, so a customer would get two receipts. Turn receipts off in the YooKassa account.",
              provider: @shop.fiscalization
            )}
          </p>
        </div>
      </section>

      <section
        :if={@settings.webhook_token}
        id="yookassa-webhook"
        class="space-y-2 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <h2 class="font-bold">{gettext("Webhook URL")}</h2>
        <p class="text-sm text-base-content/60">
          {gettext(
            "Paste this URL in the YooKassa account, section Integration, Notifications. Turn on payment.waiting_for_capture, payment.succeeded, payment.canceled and refund.succeeded."
          )}
        </p>
        <code class="block break-all rounded bg-base-200 p-2 text-xs">
          {Yookassa.webhook_url(@settings.webhook_token)}
        </code>
      </section>

      <.live_component
        module={JournalComponent}
        id="yookassa-journal"
        provider={:yookassa}
        branch_id={nil}
      />
    </div>
    """
  end
end
