defmodule DelivestWeb.Staff.IntegrationLive.YandexEdaAccess do
  use DelivestWeb, :html

  alias Delivest.Integrations.YandexEda
  alias Delivest.Integrations.YandexEda.Settings

  attr :settings, Settings, required: true
  attr :form, Phoenix.HTML.Form, required: true

  def access(assigns) do
    ~H"""
    <section
      id="yandex-eda-access"
      class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
    >
      <div>
        <h2 class="font-bold">{gettext("Access for Yandex")}</h2>
        <p class="text-sm text-base-content/60">
          {gettext(
            "Shared by every branch. Give the address, the client id and the secret to the Yandex Eda manager."
          )}
        </p>
      </div>

      <dl :if={Settings.credentials?(@settings)} class="grid gap-3 text-sm sm:grid-cols-[10rem_1fr]">
        <dt class="text-base-content/60">{gettext("Address")}</dt>
        <dd><code id="yandex-eda-base-url" class="break-all">{YandexEda.base_url()}</code></dd>
        <dt class="text-base-content/60">client_id</dt>
        <dd><code id="yandex-eda-client-id" class="break-all">{@settings.client_id}</code></dd>
        <dt class="text-base-content/60">client_secret</dt>
        <dd>
          <code id="yandex-eda-client-secret" class="break-all">{@settings.client_secret}</code>
        </dd>
      </dl>

      <button
        id="yandex-eda-rotate"
        type="button"
        class="btn btn-sm"
        phx-click="rotate"
        data-confirm={
          Settings.credentials?(@settings) &&
            gettext("Yandex will lose access until it gets the new secret. Continue?")
        }
      >
        <.icon name="hero-key" class="size-4" />
        {if Settings.credentials?(@settings),
          do: gettext("Generate a new secret"),
          else: gettext("Generate access")}
      </button>

      <.form for={@form} id="yandex-eda-shared" phx-submit="save_shared" class="space-y-4">
        <p class="text-sm text-base-content/60">
          {gettext("Yandex gives these to ask it to reload the menu right after changes.")}
        </p>
        <div class="grid gap-4 sm:grid-cols-3">
          <.input field={@form[:partner_name]} type="text" label="Partner-Name" />
          <.input field={@form[:push_client_id]} type="text" label="client_id" />
          <.input
            field={@form[:push_client_secret]}
            type="password"
            value={@form[:push_client_secret].value}
            label="client_secret"
          />
        </div>
        <div class="flex justify-end">
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </section>
    """
  end
end
