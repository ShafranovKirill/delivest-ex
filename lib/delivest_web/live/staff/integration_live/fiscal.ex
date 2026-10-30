defmodule DelivestWeb.Staff.IntegrationLive.Fiscal do
  use DelivestWeb, :live_view

  alias Delivest.{Fiscal, Identity}
  alias Delivest.Fiscal.{BranchSettings, Vat}
  alias Delivest.Integrations.Health

  on_mount {DelivestWeb.Hooks.Permission, "integrations.read"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: gettext("Receipts"),
       can_edit: Identity.can?(socket.assigns.current_staff, "integrations.update"),
       check: nil,
       kkt_issues: kkt_issues(socket.assigns.current_branch.id)
     )
     |> assign_settings(Fiscal.settings(socket.assigns.current_branch.id))}
  end

  @impl true
  def handle_event("validate", %{"fiscal" => params}, socket) do
    changeset =
      socket.assigns.settings
      |> Fiscal.change_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "fiscal"))}
  end

  def handle_event("save", %{"fiscal" => params}, socket) do
    case Fiscal.update_settings(
           socket.assigns.current_staff,
           socket.assigns.current_branch.id,
           params
         ) do
      {:ok, settings} ->
        {:noreply,
         socket |> assign_settings(settings) |> put_flash(:info, gettext("Settings saved"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, form: to_form(Map.put(changeset, :action, :update), as: "fiscal"))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Please check the highlighted fields"))}
    end
  end

  def handle_event("check", _params, socket) do
    check =
      case Fiscal.health_check(socket.assigns.current_branch.id) do
        :ok ->
          {:ok, gettext("Connected")}

        {:error, reason} ->
          {:error, gettext("Connection failed: %{reason}", reason: inspect(reason))}
      end

    {:noreply, assign(socket, check: check)}
  end

  defp kkt_issues(branch_id) do
    case Health.get(:atol, branch_id) do
      %{status: :warning, message: "kkt_issues:" <> codes} -> String.split(codes, ",")
      _status -> []
    end
  end

  defp kkt_issue_text("offline"),
    do: gettext("The cash register is not sending documents to the OFD")

  defp kkt_issue_text("fn_full"), do: gettext("The fiscal storage is more than 90% full")

  defp kkt_issue_text("fn_expiring"),
    do: gettext("The fiscal storage expires in less than 30 days")

  defp kkt_issue_text(_code), do: gettext("Needs attention")

  defp assign_settings(socket, settings) do
    settings = %{settings | atol: settings.atol || %Delivest.Integrations.AtolOnline.Settings{}}

    assign(socket,
      settings: settings,
      form: to_form(Fiscal.change_settings(settings), as: "fiscal")
    )
  end

  defp mode_options,
    do: [
      {gettext("Off"), :off},
      {gettext("Our receipts through ATOL Online"), :own},
      {gettext("Receipts are issued by the CRM or POS"), :external}
    ]

  defp sno_options,
    do: [
      {gettext("General tax system"), :osn},
      {gettext("Simplified, income"), :usn_income},
      {gettext("Simplified, income minus expenses"), :usn_income_outcome},
      {gettext("Unified agricultural"), :esn},
      {gettext("Patent"), :patent}
    ]

  defp vat_options, do: Enum.map(Vat.rates(), &{vat_label(&1), &1})

  defp vat_label(:none), do: gettext("No VAT")
  defp vat_label(rate), do: rate |> to_string() |> String.replace("vat", "") |> Kernel.<>("%")

  defp courier_card_options,
    do: [
      {gettext("We issue the receipt"), :receipt},
      {gettext("The courier terminal issues it"), :terminal}
    ]

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
        title={gettext("Receipts")}
        subtitle={
          gettext(
            "Receipts are issued when the order is handed over: for cash and card payments to the operator or our courier. Yandex Eda, Yandex Delivery and CRM orders are receipted on their side."
          )
        }
      />

      <div :if={@kkt_issues != []} id="fiscal-kkt-issues" role="alert" class="alert alert-warning">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <ul>
          <li :for={code <- @kkt_issues}>{kkt_issue_text(code)}</li>
        </ul>
      </div>

      <.form
        for={@form}
        id="fiscal-settings"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <.input
          field={@form[:mode]}
          type="select"
          label={gettext("Receipts")}
          options={mode_options()}
          disabled={not @can_edit}
        />

        <div :if={BranchSettings.own?(Ecto.Changeset.apply_changes(@form.source))} class="space-y-4">
          <.inputs_for :let={atol} field={@form[:atol]}>
            <div class="grid gap-4 sm:grid-cols-2">
              <.input
                field={atol[:login]}
                type="text"
                label={gettext("Login")}
                disabled={not @can_edit}
              />
              <.input
                field={atol[:password]}
                type="password"
                value=""
                label={gettext("Password")}
                placeholder={
                  if @settings.atol.password, do: gettext("Saved, enter a new one to replace it")
                }
                disabled={not @can_edit}
              />
              <.input
                field={atol[:group_code]}
                type="text"
                label={gettext("Group code")}
                disabled={not @can_edit}
              />
              <.input
                field={atol[:sandbox]}
                type="checkbox"
                label={gettext("Test environment")}
                disabled={not @can_edit}
              />
            </div>
          </.inputs_for>
          <p class="-mt-2 text-xs text-base-content/60">
            {gettext("ATOL Online account, the integrator settings.")}
          </p>

          <div class="grid gap-4 sm:grid-cols-2">
            <.input field={@form[:inn]} type="text" label={gettext("INN")} disabled={not @can_edit} />
            <.input
              field={@form[:sno]}
              type="select"
              label={gettext("Tax system")}
              options={sno_options()}
              disabled={not @can_edit}
            />
            <.input
              field={@form[:payment_address]}
              type="text"
              label={gettext("Place of settlement")}
              disabled={not @can_edit}
            />
            <.input
              field={@form[:email]}
              type="email"
              label={gettext("Sender email")}
              disabled={not @can_edit}
            />
            <.input
              field={@form[:vat]}
              type="select"
              label={gettext("VAT")}
              options={vat_options()}
              disabled={not @can_edit}
            />
            <.input
              field={@form[:delivery_vat]}
              type="select"
              label={gettext("Delivery VAT")}
              options={vat_options()}
              disabled={not @can_edit}
            />
            <.input
              field={@form[:courier_card]}
              type="select"
              label={gettext("Card payment to our courier")}
              options={courier_card_options()}
              disabled={not @can_edit}
            />
          </div>
        </div>

        <div class="flex flex-wrap items-center justify-end gap-3">
          <span
            :if={@check}
            id="fiscal-check"
            class={[
              "text-sm",
              elem(@check, 0) == :ok && "text-success",
              elem(@check, 0) == :error && "text-error"
            ]}
          >
            {elem(@check, 1)}
          </span>
          <button
            :if={@settings.mode == :own}
            type="button"
            phx-click="check"
            class="btn btn-ghost"
          >
            {gettext("Check the connection")}
          </button>
          <button
            :if={@can_edit}
            type="submit"
            class="btn btn-primary"
            phx-disable-with={gettext("Saving...")}
          >
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
