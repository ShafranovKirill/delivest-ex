defmodule DelivestWeb.Staff.IntegrationLive.Zvonok do
  use DelivestWeb, :live_view

  alias Delivest.Integrations.Zvonok
  alias DelivestWeb.Staff.IntegrationLive.JournalComponent

  on_mount {DelivestWeb.Hooks.Permission, "admin"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Sign-in by phone number"))
     |> assign_settings(Zvonok.get_settings())}
  end

  @impl true
  def handle_event("validate", %{"zvonok" => params}, socket) do
    changeset =
      socket.assigns.settings
      |> Zvonok.change_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "zvonok"))}
  end

  def handle_event("save", %{"zvonok" => params}, socket) do
    case Zvonok.update_settings(socket.assigns.current_staff, params) do
      {:ok, settings} ->
        {:noreply,
         socket |> assign_settings(settings) |> put_flash(:info, gettext("Settings saved"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "zvonok"))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  defp assign_settings(socket, settings) do
    assign(socket,
      settings: settings,
      form: to_form(Zvonok.change_settings(settings), as: "zvonok")
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
        title={gettext("Sign-in by phone number")}
        subtitle={
          gettext(
            "Customers sign in with a call via zvonok.com. The settings are shared by every branch."
          )
        }
      />

      <.form
        for={@form}
        id="zvonok-settings"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <div class="space-y-1">
          <.input field={@form[:enabled]} type="checkbox" label={gettext("Customer sign-in")} />
          <p class="text-xs text-base-content/60">
            {gettext(
              "When off, the site has no sign-in at all: everyone orders as a guest, signed in customers are signed out."
            )}
          </p>
        </div>

        <div class="space-y-1">
          <.input
            field={@form[:login_call_mode]}
            type="select"
            label={gettext("Sign-in call mode")}
            options={[
              {gettext("Customer calls us"), "inbound"},
              {gettext("We flash-call the customer"), "flash"}
            ]}
          />
          <p class="text-xs text-base-content/60">
            {gettext(
              "Flash call: the customer enters the last 4 digits of the incoming number. Turn it on only if flash calls are enabled in your Zvonok campaign."
            )}
          </p>
        </div>

        <div class="grid gap-4 sm:grid-cols-2">
          <.input
            field={@form[:public_key]}
            type="password"
            value={@form[:public_key].value}
            label={gettext("API key")}
          />
          <.input field={@form[:campaign_id]} type="text" label={gettext("Campaign ID")} />
        </div>

        <div class="space-y-1">
          <.input field={@form[:webhook_token]} type="text" label={gettext("Webhook token")} />
          <p class="text-xs text-base-content/60">
            {gettext(
              "Any secret string, it becomes part of the webhook URL. A random one is suggested, you can keep it."
            )}
          </p>
        </div>

        <div class="flex justify-end">
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>

      <section
        :if={@settings.webhook_token}
        id="zvonok-webhook"
        class="space-y-2 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <h2 class="font-bold">{gettext("Webhook for zvonok.com")}</h2>
        <p class="text-sm text-base-content/60">
          {gettext(
            "Paste this URL as a whole into the postback of the zvonok.com campaign. {ct_call_id} and {ct_phone} are Zvonok macros, it fills them in by itself."
          )}
        </p>
        <code class="block break-all rounded bg-base-200 p-2 text-xs">
          {Zvonok.webhook_url(@settings.webhook_token)}
        </code>
      </section>

      <.live_component
        module={JournalComponent}
        id="zvonok-journal"
        provider={:zvonok}
        branch_id={nil}
      />
    </div>
    """
  end
end
