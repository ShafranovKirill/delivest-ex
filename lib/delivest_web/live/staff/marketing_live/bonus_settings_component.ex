defmodule DelivestWeb.Staff.MarketingLive.BonusSettingsComponent do
  use DelivestWeb, :live_component

  alias Delivest.{Franchise, Identity}

  @fields ~w(loyalty_per_rubles loyalty_stars loyalty_expire_days)

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if socket.assigns[:form],
      do: {:ok, socket},
      else: {:ok, assign_form(socket, Franchise.change_settings(Franchise.get_settings()))}
  end

  @impl true
  def handle_event("validate", %{"settings" => params}, socket) do
    if allowed?(socket) do
      changeset =
        Franchise.get_settings()
        |> Franchise.change_settings(Map.take(params, @fields))
        |> Map.put(:action, :validate)

      {:noreply, assign_form(socket, changeset)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save", %{"settings" => params}, socket) do
    if allowed?(socket) do
      case Franchise.update_settings(socket.assigns.current_staff, Map.take(params, @fields)) do
        {:ok, settings} ->
          {:noreply,
           socket
           |> assign_form(Franchise.change_settings(settings))
           |> put_flash(:info, gettext("Settings saved"))}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}

        {:error, :forbidden} ->
          {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  defp allowed?(socket),
    do: Identity.can?(socket.assigns.current_staff, "franchise.update")

  defp assign_form(socket, changeset),
    do: assign(socket, form: to_form(changeset, as: "settings"))

  @impl true
  def render(assigns) do
    ~H"""
    <div id="global-bonus-settings-component">
      <section
        :if={Identity.can?(@current_staff, "franchise.update")}
        id="common-bonuses"
        class="space-y-3"
      >
        <h2 class="mb-3 text-lg font-semibold">{gettext("Common bonus settings")}</h2>
        <.form
          for={@form}
          id="common-bonuses-form"
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
          class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
        >
          <div class="grid gap-4 sm:grid-cols-2">
            <.input
              field={@form[:loyalty_per_rubles]}
              type="number"
              min="1"
              label={gettext("For every, ₽")}
            />
            <.input field={@form[:loyalty_stars]} type="number" min="1" label={gettext("Stars")} />
          </div>
          <.input
            field={@form[:loyalty_expire_days]}
            type="number"
            min="1"
            label={gettext("Stars expire after, days")}
          />
          <p class="text-sm text-base-content/60">
            {gettext("These rules apply to every branch.")}
            {gettext(
              "Stars are counted from the order total after discounts, without delivery, and rounded down. They are credited when the order is completed."
            )}
          </p>
        </.form>
      </section>
    </div>
    """
  end
end
