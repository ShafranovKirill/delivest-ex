defmodule DelivestWeb.Staff.IntegrationLive.YandexAds do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Integrations.YandexAds
  alias Delivest.Integrations.YandexAds.Secret

  on_mount {DelivestWeb.Hooks.Permission, "admin"}

  @secrets ~w(direct_token metrika_token refresh_token measurement_token)a

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: gettext("Yandex Direct and Metrika"),
       branches: Identity.list_branch_for_staff(socket.assigns.current_staff),
       encryption_ready: Secret.configured?(),
       checks: nil,
       operation: nil
     )
     |> assign_settings(YandexAds.get_settings())}
  end

  @impl true
  def handle_event("validate", %{"yandex_ads" => attrs}, socket) do
    form =
      socket.assigns.settings |> YandexAds.change_settings(attrs) |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(form, as: :yandex_ads))}
  end

  def handle_event("save", %{"yandex_ads" => attrs}, socket) do
    case YandexAds.update_settings(socket.assigns.current_staff, attrs) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign_settings(settings)
         |> assign(checks: nil)
         |> put_flash(:info, gettext("Settings saved"))
         |> push_event("staff:form-saved", %{})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :yandex_ads))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  def handle_event("check", _params, socket) do
    if Identity.can?(socket.assigns.current_staff, "admin") do
      staff = socket.assigns.current_staff

      {:noreply,
       socket
       |> assign(checks: :checking)
       |> start_async(:check_connections, fn -> YandexAds.check_connections(staff) end)}
    else
      {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  def handle_event("ensure_goal", _params, socket), do: run_operation(socket, :goal)

  def handle_event("ensure_funnel_goals", _params, socket),
    do: run_operation(socket, :funnel_goals)

  def handle_event("refresh_token", _params, socket), do: run_operation(socket, :refresh)

  def handle_event("register_feed", %{"branch" => branch_id}, socket),
    do: run_operation(socket, {:feed, branch_id})

  defp run_operation(socket, operation) do
    if Identity.can?(socket.assigns.current_staff, "admin") and is_nil(socket.assigns.operation) do
      staff = socket.assigns.current_staff

      {:noreply,
       socket
       |> assign(operation: operation)
       |> start_async(:yandex_operation, fn ->
         case operation do
           :goal -> YandexAds.ensure_goal(staff)
           :funnel_goals -> YandexAds.ensure_funnel_goals(staff)
           :refresh -> YandexAds.refresh_connection(staff)
           {:feed, branch_id} -> YandexAds.register_branch_feed(staff, branch_id)
         end
       end)}
    else
      {:noreply, put_flash(socket, :error, gettext("Action unavailable"))}
    end
  end

  @impl true
  def handle_async(:check_connections, {:ok, checks}, socket),
    do: {:noreply, assign(socket, checks: checks)}

  def handle_async(:check_connections, {:exit, _reason}, socket),
    do:
      {:noreply, assign(socket, checks: %{direct: {:error, :failed}, metrika: {:error, :failed}})}

  def handle_async(:yandex_operation, {:ok, {:ok, _result}}, socket),
    do:
      {:noreply,
       socket
       |> assign(operation: nil)
       |> assign_settings(YandexAds.get_settings())
       |> put_flash(
         :info,
         gettext("Yandex operation completed. Check the result in your account.")
       )}

  def handle_async(:yandex_operation, _result, socket),
    do:
      {:noreply,
       socket
       |> assign(operation: nil)
       |> put_flash(
         :error,
         gettext("Yandex operation failed. Check settings and account permissions.")
       )}

  defp assign_settings(socket, settings) do
    # Decrypted secrets must never become HTML input values or LiveView diffs.
    display = Enum.reduce(@secrets, settings, &Map.put(&2, &1, nil))

    assign(socket,
      settings: settings,
      saved_secrets: Map.new(@secrets, &{&1, is_binary(Map.get(settings, &1))}),
      form: to_form(YandexAds.change_settings(display, %{}), as: :yandex_ads)
    )
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header back={~p"/staff/integrations"} title={gettext("Yandex Direct and Metrika")}>
      <:actions>
        <button
          type="submit"
          form="yandex-ads-settings"
          class="btn btn-primary"
          phx-disable-with={gettext("Saving...")}
        >
          {gettext("Save")}
        </button>
      </:actions>
    </.page_header>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <section class="rounded-box border border-base-300 bg-base-100 p-5 space-y-3">
        <p>
          {gettext(
            "Connect your counter and advertising account. Campaigns and budgets remain in Direct."
          )}
        </p>
        <p class="text-sm text-base-content/70">
          {gettext(
            "Collection starts when the menu opens after you enable it and approve the privacy policy. Webvisor is off."
          )}
        </p>
        <p :if={!@encryption_ready} id="yandex-encryption-required" role="status" class="text-warning">
          {gettext(
            "Credential storage is unavailable. Configure YANDEX_ADS_ENCRYPTION_KEY on the server before saving tokens."
          )}
        </p>
        <p
          :if={@settings.credential_error}
          id="yandex-credentials-unavailable"
          role="alert"
          class="text-error"
        >
          {gettext(
            "Saved credentials cannot be decrypted. Restore the original encryption key; collection and sending are stopped."
          )}
        </p>
        <.link navigate={~p"/staff/analytics/advertising"} class="link link-primary">{gettext(
          "Advertising analytics"
        )}</.link>
      </section>

      <.form
        for={@form}
        id="yandex-ads-settings"
        phx-change="validate"
        phx-submit="save"
        data-staff-dirty
        class="space-y-5"
      >
        <section class="rounded-box border border-base-300 bg-base-100 p-5 space-y-4">
          <h2 class="text-lg font-bold">{gettext("Collection and access")}</h2>
          <.input
            field={@form[:enabled]}
            type="checkbox"
            label={gettext("Enable Yandex integration")}
          />
          <.input
            field={@form[:branch_ids]}
            type="select"
            multiple
            options={Enum.map(@branches, &{&1.name, &1.id})}
            label={gettext("Branches")}
          />
          <.input
            field={@form[:privacy_approved]}
            type="checkbox"
            label={
              gettext(
                "I have reviewed the privacy policy and approved analytics collection for these branches"
              )
            }
          />
          <.input
            field={@form[:browser_enabled]}
            type="checkbox"
            label={gettext("Metrika: visits and funnel")}
          />
          <.input
            field={@form[:conversions_enabled]}
            type="checkbox"
            label={gettext("Send completed orders as offline conversions")}
          />
          <.input
            field={@form[:ecommerce_enabled]}
            type="checkbox"
            label={gettext("Send product events and server purchases")}
          />
          <.input
            field={@form[:feed_enabled]}
            type="checkbox"
            label={gettext("Publish product feeds")}
          />
          <.input
            field={@form[:costs_enabled]}
            type="checkbox"
            label={gettext("Import advertising costs")}
          />
          <p class="text-sm text-base-content/60">
            {gettext(
              "Platform feature permissions also apply. Re-enabling collection does not restore the disabled period."
            )}
          </p>
        </section>

        <section class="rounded-box border border-base-300 bg-base-100 p-5 space-y-4">
          <h2 class="text-lg font-bold">{gettext("Counter and account")}</h2>
          <.input
            field={@form[:counter_id]}
            label={gettext("Metrika counter ID")}
            inputmode="numeric"
          />
          <.input field={@form[:goal]} label={gettext("Completed order goal identifier")} />
          <.input
            field={@form[:client_login]}
            label={gettext("Direct advertiser login (for agency access)")}
          />
          <.input field={@form[:timezone]} label={gettext("Advertising account time zone")} />
          <.input
            field={@form[:currency]}
            type="select"
            options={[{"RUB", "RUB"}]}
            label={gettext("Currency")}
          />
          <.input
            field={@form[:include_vat]}
            type="checkbox"
            label={gettext("Include VAT in advertising costs")}
          />
          <%= for {key, label} <- secret_labels() do %>
            <div>
              <.input
                field={@form[key]}
                type="password"
                value=""
                autocomplete="new-password"
                label={label}
              />
              <p
                :if={@saved_secrets[key]}
                id={"yandex-#{key}-saved"}
                class="text-xs text-base-content/60"
              >
                {gettext("Saved securely. Leave blank to keep the existing credential.")}
              </p>
            </div>
          <% end %>
        </section>
      </.form>

      <section class="rounded-box border border-base-300 bg-base-100 p-5 space-y-4">
        <h2 class="text-lg font-bold">{gettext("Connection checks")}</h2>
        <a
          id="yandex-oauth-connect"
          href="/staff/integrations/yandex-ads/connect"
          class="btn btn-primary"
        >
          {gettext("Connect with Yandex")}
        </a>
        <button
          id="yandex-check"
          type="button"
          phx-click="check"
          disabled={@checks == :checking}
          class="btn btn-outline"
        >
          {if @checks == :checking,
            do: gettext("Checking..."),
            else: gettext("Check saved connection")}
        </button>
        <p :if={is_nil(@checks)} class="text-sm text-base-content/60">
          {gettext("Not checked. Saved credentials alone do not confirm access.")}
        </p>
        <dl :if={is_map(@checks)} id="yandex-check-results" class="space-y-2">
          <div :for={{provider, result} <- @checks} class="flex gap-3">
            <dt>{provider_label(provider)}</dt><dd>{check_label(result)}</dd>
          </div>
        </dl>
        <div class="flex flex-wrap gap-3">
          <button
            id="yandex-ensure-goal"
            type="button"
            phx-click="ensure_goal"
            disabled={not is_nil(@operation)}
            class="btn btn-outline"
          >
            {gettext("Find or create the completed order goal")}
          </button>
          <button
            id="yandex-refresh-token"
            type="button"
            phx-click="refresh_token"
            disabled={not is_nil(@operation)}
            class="btn btn-outline"
          >
            {gettext("Refresh OAuth access")}
          </button>
          <button
            id="yandex-ensure-funnel-goals"
            type="button"
            phx-click="ensure_funnel_goals"
            disabled={not is_nil(@operation)}
            class="btn btn-outline"
          >
            {gettext("Configure menu and checkout goals")}
          </button>
        </div>
        <p class="text-sm text-base-content/60">
          {gettext(
            "Use one completed order goal for campaign optimization. Creating the goal does not start or change campaigns."
          )}
        </p>
      </section>

      <section
        :if={@settings.feed_enabled}
        id="yandex-feeds"
        class="rounded-box border border-base-300 bg-base-100 p-5 space-y-3"
      >
        <h2 class="text-lg font-bold">{gettext("Product feeds")}</h2>
        <p class="text-sm text-base-content/70">
          {gettext(
            "A feed is available only for an enabled branch with the platform feature granted. Yandex may retain a previously downloaded copy after disabling it."
          )}
        </p>
        <div :for={branch <- Enum.filter(@branches, &(&1.id in @settings.branch_ids))}>
          <a
            href={"/seo/branches/#{URI.encode(branch.slug, &URI.char_unreserved?/1)}/catalog.xml"}
            target="_blank"
            rel="noopener"
            class="link link-primary"
          >{branch.name}</a>
          <button
            type="button"
            id={"yandex-register-feed-#{branch.id}"}
            phx-click="register_feed"
            phx-value-branch={branch.id}
            disabled={not is_nil(@operation)}
            class="btn btn-outline btn-sm ml-3"
          >
            {gettext("Register feed in Direct")}
          </button>
        </div>
      </section>
    </div>
    """
  end

  defp secret_labels do
    [
      direct_token: gettext("Direct OAuth token"),
      metrika_token: gettext("Metrika OAuth token"),
      refresh_token: gettext("OAuth refresh token"),
      measurement_token: gettext("Measurement Protocol token")
    ]
  end

  defp provider_label(:direct), do: "Direct"
  defp provider_label(:metrika), do: "Metrika"
  defp provider_label(:metrika_goal), do: gettext("Completed order goal")
  defp provider_label(_), do: gettext("Connection")
  defp check_label({:ok, _}), do: gettext("Connection checked")
  defp check_label(:ok), do: gettext("Connection checked")

  defp check_label(_),
    do: gettext("Access not confirmed. Review credentials and account permissions.")
end
