defmodule DelivestWeb.Staff.FinanceLive.Payments do
  use DelivestWeb, :live_view

  alias Delivest.{Identity, Payments}
  alias Delivest.Identity.Branch.PaymentSettings
  alias Delivest.Integrations.Yookassa

  on_mount {DelivestWeb.Hooks.Permission, "finance.read"}

  @impl true
  def mount(_params, _session, socket) do
    branch = socket.assigns.current_branch

    {:ok,
     socket
     |> assign(
       page_title: gettext("Payment"),
       can_edit: Identity.can?(socket.assigns.current_staff, "finance.update"),
       online_ready: Yookassa.ready?()
     )
     |> assign_form(PaymentSettings.changeset(Payments.settings(branch), %{}))}
  end

  @impl true
  def handle_event("validate", %{"payments" => params}, socket) do
    changeset =
      socket.assigns.current_branch
      |> Payments.settings()
      |> PaymentSettings.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"payments" => params}, socket) do
    case Identity.update_payments(
           socket.assigns.current_staff,
           socket.assigns.current_branch,
           params
         ) do
      {:ok, branch} ->
        {:noreply,
         socket
         |> assign(current_branch: branch)
         |> assign_form(PaymentSettings.changeset(Payments.settings(branch), %{}))
         |> put_flash(:info, gettext("Settings saved"))}

      {:error, :info, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to save"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  defp assign_form(socket, changeset),
    do: assign(socket, form: to_form(changeset, as: "payments"))

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6 max-w-3xl">
      <.page_header
        title={gettext("Payment")}
        subtitle={gettext("How customers of this branch can pay for an order.")}
      />

      <.form
        for={@form}
        id="payments-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <.input
          field={@form[:cash]}
          type="checkbox"
          label={gettext("Cash to the courier")}
          disabled={not @can_edit}
        />
        <.input
          field={@form[:card_offline]}
          type="checkbox"
          label={gettext("Card to the courier")}
          disabled={not @can_edit}
        />
        <.input
          field={@form[:online]}
          type="checkbox"
          label={gettext("Online payment (YooKassa)")}
          disabled={not @can_edit or not @online_ready}
        />
        <p :if={not @online_ready} id="online-unavailable" class="text-sm text-warning pl-7">
          {gettext("Connect YooKassa and pass the connection check in the integrations first.")}
          <.link
            :if={Identity.can?(@current_staff, "admin")}
            navigate={~p"/staff/b/#{@current_branch}/integrations/yookassa"}
            class="link"
          >
            {gettext("Open YooKassa settings")}
          </.link>
        </p>
        <div :if={@form[:online].value in [true, "true"]} class="pl-7 space-y-1">
          <.input
            field={@form[:skip_confirmation_call]}
            type="checkbox"
            label={gettext("Do not call the customer to confirm paid orders")}
            disabled={not @can_edit}
          />
          <p class="text-sm text-base-content/60">
            {gettext(
              "A paid order is accepted automatically and the customer sees \"Order accepted, we started cooking\". If the operator changes the order, they call the customer."
            )}
          </p>
        </div>
        <p :if={@form[:cash].errors != []} class="text-sm text-error">
          {gettext("Enable at least one payment method")}
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
