defmodule DelivestWeb.Staff.FranchiseLive.SettingsFormComponent do
  use DelivestWeb, :live_component

  alias Delivest.Franchise
  alias DelivestWeb.Staff.FranchiseLive.FranchiseHelpers

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if socket.assigns[:form],
      do: {:ok, socket},
      else: {:ok, assign_form(socket, Franchise.change_settings(assigns.settings))}
  end

  @impl true
  def handle_event("validate", %{"settings" => params}, socket) do
    changeset =
      socket.assigns.settings
      |> Franchise.change_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"settings" => params}, socket) do
    case Franchise.update_settings(socket.assigns.current_staff, params) do
      {:ok, settings} ->
        send(self(), {__MODULE__, {:saved, settings}})

        {:noreply,
         socket |> assign(settings: settings) |> assign_form(Franchise.change_settings(settings))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :forbidden} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("custom_dark_color", _params, socket),
    do: {:noreply, put_dark_color(socket, socket.assigns.color)}

  def handle_event("auto_dark_color", _params, socket),
    do: {:noreply, put_dark_color(socket, "")}

  defp put_dark_color(socket, value) do
    params = Map.put(socket.assigns.form.params, "dark_primary_color", value)

    changeset =
      socket.assigns.settings
      |> Franchise.change_settings(params)
      |> Map.put(:action, :validate)

    assign_form(socket, changeset)
  end

  defp assign_form(socket, changeset) do
    assign(socket,
      form: to_form(changeset, as: "settings"),
      color: Ecto.Changeset.get_field(changeset, :primary_color),
      dark_color: Ecto.Changeset.get_field(changeset, :dark_primary_color)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={@form}
        id="franchise-settings-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <section class="p-5 bg-base-100 rounded-box border border-base-200 shadow-sm space-y-4">
          <h2 class="font-bold text-lg">{gettext("Brand")}</h2>
          <.input field={@form[:name]} type="text" label={gettext("Name")} maxlength="60" />
          <.input
            field={@form[:description]}
            type="textarea"
            rows="2"
            label={gettext("Site description for search engines")}
            maxlength="300"
          />

          <div class="space-y-2">
            <span class="text-sm font-medium">{gettext("Primary color")}</span>
            <div class="flex flex-wrap items-center gap-3">
              <input
                type="color"
                name="settings[primary_color]"
                id="franchise-color"
                value={@color}
                class="h-10 w-16 cursor-pointer rounded-lg border border-base-300 bg-base-100 p-1"
              />
              <span class="font-mono text-sm uppercase">{@color}</span>
              <span
                id="franchise-color-preview"
                class="rounded-full px-5 py-2 text-sm font-semibold text-white"
                style={"background-color: #{@color}"}
              >
                {gettext("Place order")}
              </span>
            </div>
            <p
              :if={!FranchiseHelpers.readable_on_white?(@color)}
              id="franchise-color-warning"
              class="text-xs text-warning"
            >
              {gettext("White text is hard to read on this color. Choose a darker one.")}
            </p>
            <p
              :for={error <- @form[:primary_color].errors}
              class="text-xs text-error"
            >
              {translate_error(error)}
            </p>
          </div>

          <div id="franchise-dark-color" class="space-y-2">
            <span class="text-sm font-medium">{gettext("Color in the dark theme")}</span>
            <div :if={is_nil(@dark_color)} class="flex flex-wrap items-center gap-3">
              <input type="hidden" name="settings[dark_primary_color]" value="" />
              <span class="text-sm text-base-content/60">
                {gettext("Picked automatically from the primary color so it reads well.")}
              </span>
              <button
                type="button"
                id="franchise-dark-color-custom"
                phx-click="custom_dark_color"
                phx-target={@myself}
                class="btn btn-sm btn-ghost"
              >
                {gettext("Choose my own")}
              </button>
            </div>
            <div :if={@dark_color} class="flex flex-wrap items-center gap-3">
              <input
                type="color"
                name="settings[dark_primary_color]"
                id="franchise-dark-color-input"
                value={@dark_color}
                class="h-10 w-16 cursor-pointer rounded-lg border border-base-300 bg-base-100 p-1"
              />
              <span class="font-mono text-sm uppercase">{@dark_color}</span>
              <span
                id="franchise-dark-color-preview"
                class="flex items-center gap-3 rounded-full bg-[#17171b] py-1 pl-4 pr-1"
              >
                <span class="text-sm font-semibold" style={"color: #{@dark_color}"}>
                  {gettext("Delivery")}
                </span>
                <span
                  class="rounded-full px-4 py-1.5 text-sm font-semibold text-white"
                  style={"background-color: #{@dark_color}"}
                >
                  {gettext("Place order")}
                </span>
              </span>
              <button
                type="button"
                id="franchise-dark-color-auto"
                phx-click="auto_dark_color"
                phx-target={@myself}
                class="btn btn-sm btn-ghost"
              >
                {gettext("Pick automatically")}
              </button>
            </div>
            <p :if={@dark_color} class="text-xs text-base-content/60">
              {gettext(
                "If the color is hard to read on a dark background, the site makes it lighter."
              )}
            </p>
            <p
              :for={error <- @form[:dark_primary_color].errors}
              class="text-xs text-error"
            >
              {translate_error(error)}
            </p>
          </div>
        </section>

        <section class="p-5 bg-base-100 rounded-box border border-base-200 shadow-sm space-y-4">
          <div>
            <h2 class="font-bold text-lg">{gettext("Seller details")}</h2>
            <p class="text-sm text-base-content/60">
              {gettext("Shown in the site footer and inserted into the legal documents.")}
            </p>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-[8rem_1fr] gap-x-3">
            <.input
              field={@form[:legal_form]}
              type="text"
              label={gettext("Legal form")}
              placeholder={gettext("LLC")}
              maxlength="20"
            />
            <.input
              field={@form[:legal_name]}
              type="text"
              label={gettext("Legal name")}
              maxlength="200"
            />
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-3">
            <.input field={@form[:inn]} type="text" label={gettext("INN")} inputmode="numeric" />
            <.input
              field={@form[:ogrn]}
              type="text"
              label={gettext("OGRN / OGRNIP")}
              inputmode="numeric"
            />
            <.input field={@form[:email]} type="email" label={gettext("Email for requests")} />
            <.input field={@form[:phone]} type="tel" label={gettext("Phone for requests")} />
          </div>
          <.input
            field={@form[:legal_address]}
            type="textarea"
            rows="2"
            label={gettext("Legal address")}
            maxlength="300"
          />
        </section>

        <div class="flex justify-end">
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
