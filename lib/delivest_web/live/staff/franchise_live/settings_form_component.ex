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

  defp assign_form(socket, changeset) do
    color = Ecto.Changeset.get_field(changeset, :primary_color)
    assign(socket, form: to_form(changeset, as: "settings"), color: color)
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
