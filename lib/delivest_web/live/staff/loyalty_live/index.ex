defmodule DelivestWeb.Staff.LoyaltyLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.{Identity, Loyalty}
  alias Delivest.Identity.Branch.LoyaltySettings

  on_mount {DelivestWeb.Hooks.GatewayArea, :loyalty}
  on_mount {DelivestWeb.Hooks.Permission, "promotions.read"}

  @impl true
  def mount(_params, _session, socket) do
    branch = socket.assigns.current_branch

    {:ok,
     socket
     |> assign(
       page_title: gettext("Loyalty"),
       can_edit: Identity.can?(socket.assigns.current_staff, "promotions.update"),
       summary: Loyalty.summary(branch.id)
     )
     |> assign_form(LoyaltySettings.changeset(Loyalty.settings(branch), %{}))}
  end

  @impl true
  def handle_event("validate", %{"loyalty" => params}, socket) do
    changeset =
      socket.assigns.current_branch
      |> Loyalty.settings()
      |> LoyaltySettings.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"loyalty" => params}, socket) do
    case Identity.update_loyalty(
           socket.assigns.current_staff,
           socket.assigns.current_branch,
           params
         ) do
      {:ok, branch} ->
        {:noreply,
         socket
         |> assign(current_branch: branch)
         |> assign_form(LoyaltySettings.changeset(Loyalty.settings(branch), %{}))
         |> put_flash(:info, gettext("Settings saved"))}

      {:error, :info, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign_form(Map.put(changeset, :action, :validate))
         |> put_flash(:error, gettext("Failed to save"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, form: to_form(changeset, as: "loyalty"))

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6 max-w-3xl">
      <.page_header
        title={gettext("Loyalty")}
        subtitle={gettext("Customers earn stars for completed orders.")}
      />

      <div id="loyalty-summary" class="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <div
          :for={
            {key, label} <- [
              {:issued, gettext("Stars issued")},
              {:reversed, gettext("Stars returned")},
              {:expired, gettext("Expired")},
              {:liability, gettext("Balance owed")}
            ]
          }
          id={"loyalty-summary-#{key}"}
          class="rounded-box border border-base-300 bg-base-100 p-4"
        >
          <div class="text-sm text-base-content/60">{label}</div>
          <div class="mt-1 flex items-center gap-1 text-2xl font-bold text-amber-500">
            <.icon name="hero-star-solid" class="size-5" />
            {Map.fetch!(@summary, key)}
          </div>
        </div>
      </div>

      <.form
        for={@form}
        id="loyalty-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <.input
          field={@form[:enabled]}
          type="checkbox"
          label={gettext("Loyalty program in this branch")}
          disabled={not @can_edit}
        />
        <div class="grid sm:grid-cols-2 gap-4">
          <.input
            field={@form[:per_rubles]}
            type="number"
            min="1"
            label={gettext("For every, ₽")}
            disabled={not @can_edit}
          />
          <.input
            field={@form[:stars]}
            type="number"
            min="1"
            label={gettext("Stars")}
            disabled={not @can_edit}
          />
        </div>
        <.input
          field={@form[:expire_days]}
          type="number"
          min="1"
          label={gettext("Stars expire after, days")}
          disabled={not @can_edit}
        />
        <.input
          field={@form[:spend_enabled]}
          type="checkbox"
          label={gettext("Customers can pay part of an order with stars")}
          disabled={not @can_edit}
        />
        <.input
          :if={@form[:spend_enabled].value in [true, "true"]}
          field={@form[:max_percent]}
          type="number"
          min="1"
          max="100"
          label={gettext("At most, % of the order total")}
          disabled={not @can_edit}
        />
        <p class="text-sm text-base-content/60">
          {gettext(
            "Stars are counted from the order total after discounts, without delivery, and rounded down. They are credited when the order is completed."
          )}
        </p>
        <div :if={@can_edit} class="flex justify-end">
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
