defmodule DelivestWeb.Staff.IntegrationLive.YandexEda do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Integrations.YandexEda
  alias DelivestWeb.Staff.IntegrationLive.{YandexEdaAccess, YandexEdaMenu}

  on_mount {DelivestWeb.Hooks.Permission, "branches.read"}

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff

    {:ok,
     socket
     |> assign(
       page_title: gettext("Yandex Eda"),
       can_edit_shared: Identity.can?(staff, "admin"),
       can_edit_branch: Identity.can?(staff, "branches.update"),
       can_edit_products: Identity.can?(staff, "products.update")
     )
     |> assign_shared(YandexEda.get_settings())
     |> assign_branch(YandexEda.get_branch_settings(socket.assigns.current_branch.id))
     |> load_menu()}
  end

  @impl true
  def handle_event("validate", %{"yandex_eda" => params}, socket) do
    changeset =
      socket.assigns.branch_settings
      |> YandexEda.change_branch_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "yandex_eda"))}
  end

  def handle_event("save", %{"yandex_eda" => params}, socket) do
    socket.assigns.current_staff
    |> YandexEda.update_branch_settings(socket.assigns.current_branch.id, params)
    |> case do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign_branch(settings)
         |> load_menu()
         |> put_flash(:info, gettext("Settings saved"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "yandex_eda"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("save_shared", %{"yandex_eda_shared" => params}, socket) do
    case YandexEda.update_settings(socket.assigns.current_staff, params) do
      {:ok, settings} ->
        {:noreply,
         socket |> assign_shared(settings) |> put_flash(:info, gettext("Settings saved"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, shared_form: to_form(changeset, as: "yandex_eda_shared"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("rotate", _params, socket) do
    case YandexEda.rotate_credentials(socket.assigns.current_staff) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign_shared(settings)
         |> put_flash(:info, gettext("New access for Yandex Eda is generated"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("product", %{"product_id" => product_id} = params, socket) do
    attrs = Map.take(params, ["enabled", "price"])

    case YandexEda.update_product(socket.assigns.current_staff, product_id, attrs) do
      {:ok, _channel_product} ->
        {:noreply, load_menu(socket)}

      {:error, reason} ->
        {:noreply, socket |> load_menu() |> put_flash(:error, error_message(reason))}
    end
  end

  defp assign_shared(socket, settings),
    do:
      assign(socket,
        shared: settings,
        shared_form: to_form(YandexEda.change_settings(settings), as: "yandex_eda_shared")
      )

  defp assign_branch(socket, settings),
    do:
      assign(socket,
        branch_settings: settings,
        form: to_form(YandexEda.change_branch_settings(settings), as: "yandex_eda")
      )

  defp load_menu(socket) do
    case YandexEda.menu(socket.assigns.current_branch.id) do
      {:ok, menu} -> assign(socket, menu: menu)
      {:error, _reason} -> assign(socket, menu: [])
    end
  end

  defp error_message(:forbidden), do: gettext("Permission denied")
  defp error_message(_reason), do: gettext("Failed to save")

  defp accept_mode_options,
    do: [{gettext("Automatically"), "auto"}, {gettext("Manually by staff"), "manual"}]

  defp round_options, do: [{"1 ₽", 1}, {"5 ₽", 5}, {"10 ₽", 10}]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6 max-w-5xl">
      <.link navigate={~p"/staff/integrations"} class="btn btn-ghost btn-sm -ml-2">
        <.icon name="hero-arrow-left" class="size-4" /> {gettext("Integrations")}
      </.link>

      <.page_header
        title={gettext("Yandex Eda")}
        subtitle={
          gettext(
            "Orders from Yandex Eda and Delivery Club come to the app. Yandex reads the menu, the stop list and order statuses from us."
          )
        }
      />

      <YandexEdaAccess.access
        :if={@can_edit_shared}
        settings={@shared}
        form={@shared_form}
      />

      <.form
        for={@form}
        id="yandex-eda-branch"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <div>
          <h2 class="font-bold">{gettext("Branch")} «{@current_branch.name}»</h2>
          <p class="text-sm text-base-content/60">
            {gettext("The branch is a separate restaurant in Yandex Eda, its id is %{id}.",
              id: @current_branch.id
            )}
          </p>
        </div>

        <.input
          field={@form[:enabled]}
          type="checkbox"
          label={gettext("Take orders from Yandex Eda")}
          disabled={not @can_edit_branch}
        />

        <div class="grid gap-4 sm:grid-cols-2">
          <.input
            field={@form[:accept_mode]}
            type="select"
            label={gettext("Order confirmation")}
            options={accept_mode_options()}
            disabled={not @can_edit_branch}
          />
          <.input
            :if={@form[:accept_mode].value in [:manual, "manual"]}
            field={@form[:accept_minutes]}
            type="number"
            label={gettext("Minutes to confirm")}
            disabled={not @can_edit_branch}
          />
        </div>

        <div class="grid gap-4 sm:grid-cols-2">
          <.input
            field={@form[:markup_percent]}
            type="number"
            label={gettext("Price markup, %")}
            disabled={not @can_edit_branch}
          />
          <.input
            field={@form[:round_to]}
            type="select"
            label={gettext("Round marked up prices up to")}
            options={round_options()}
            disabled={not @can_edit_branch}
          />
        </div>

        <div :if={@can_edit_branch} class="flex justify-end">
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>

      <YandexEdaMenu.menu
        menu={@menu}
        enabled={@branch_settings.enabled}
        can_edit={@can_edit_products}
      />
    </div>
    """
  end
end
