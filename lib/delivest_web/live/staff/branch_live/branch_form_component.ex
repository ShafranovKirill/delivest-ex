defmodule DelivestWeb.Staff.BranchLive.BranchFormComponent do
  use DelivestWeb, :live_component

  alias Delivest.Identity
  alias DelivestWeb.Staff.BranchLive.{BranchForm, WorkingHoursComponent}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    changeset = BranchForm.changeset(BranchForm.for_branch(socket.assigns.branch), %{})

    {:ok, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"branch_form" => params}, socket) do
    changeset =
      socket.assigns.branch
      |> BranchForm.for_branch()
      |> BranchForm.changeset(with_working_hours(params, socket))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"branch_form" => params}, socket) do
    socket.assigns.branch
    |> BranchForm.for_branch()
    |> BranchForm.changeset(with_working_hours(params, socket))
    |> save(socket)
  end

  defp with_working_hours(params, socket) do
    current = Ecto.Changeset.get_field(socket.assigns.form.source, :working_hours) || %{}
    Map.put(params, "working_hours", Map.merge(current, params["working_hours"] || %{}))
  end

  defp save(%Ecto.Changeset{valid?: false} = changeset, socket),
    do: {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :insert)))}

  defp save(changeset, socket) do
    {branch_params, info_params} = BranchForm.to_params(changeset)

    case persist(socket.assigns, branch_params, info_params) do
      {:ok, _branch} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Branch saved successfully"))
         |> push_navigate(to: ~p"/staff/branches")}

      {:error, _step, %Ecto.Changeset{} = error} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Please check the highlighted fields"))
         |> assign(form: to_form(copy_errors(changeset, error)))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  defp persist(%{action: :new, current_staff: staff}, branch_params, info_params),
    do: Identity.create_branch(staff, branch_params, info_params)

  defp persist(
         %{action: :edit, current_staff: staff, branch: branch},
         branch_params,
         info_params
       ),
       do: Identity.update_branch(staff, branch, branch_params, info_params)

  defp copy_errors(changeset, error) do
    error.errors
    |> Enum.reduce(changeset, fn {field, {message, opts}}, acc ->
      Ecto.Changeset.add_error(acc, field, message, opts)
    end)
    |> Map.put(:action, :insert)
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <section id={@id} class="scroll-mt-24 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6">
      <header class="mb-4">
        <h2 class="text-lg font-bold">{@title}</h2>
        <p :if={@description} class="text-sm text-base-content/60">{@description}</p>
      </header>
      <div class="space-y-4">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  defp sections do
    [
      {"branch-general", gettext("General")},
      {"branch-schedule", gettext("Working Hours")},
      {"branch-links", gettext("Social Links & Messengers")},
      {"branch-map", gettext("YCart Settings")}
    ]
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :sections, sections())

    ~H"""
    <div class="grid gap-6 lg:grid-cols-[220px_minmax(0,1fr)]">
      <nav class="hidden lg:block">
        <ul class="menu sticky top-24 w-full rounded-box border border-base-300 bg-base-100 p-2">
          <li :for={{id, label} <- @sections}><a href={"##{id}"}>{label}</a></li>
        </ul>
      </nav>

      <.form
        for={@form}
        id="branch-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.section id="branch-general" title={gettext("General")}>
          <div class="grid gap-4 sm:grid-cols-2">
            <.input field={@form[:name]} type="text" label={gettext("Branch Name")} required />
            <.input field={@form[:slug]} type="text" label={gettext("Branch Slug")} required />
            <.input field={@form[:city]} type="text" label={gettext("Delivery city")} />
            <.input field={@form[:address]} type="text" label={gettext("Address")} />
            <.input field={@form[:phone_number]} type="text" label={gettext("Phone Number")} />
            <.input
              field={@form[:delivery_time]}
              type="number"
              label={gettext("Delivery Time (minutes)")}
            />
          </div>
          <.input field={@form[:is_active]} type="checkbox" label={gettext("Active")} />
        </.section>

        <.section id="branch-schedule" title={gettext("Working Hours")}>
          <.live_component
            module={WorkingHoursComponent}
            id="working-hours-editor"
            working_hours={Ecto.Changeset.get_field(@form.source, :working_hours) || %{}}
          />
        </.section>

        <.section id="branch-links" title={gettext("Social Links & Messengers")}>
          <div class="grid gap-4 sm:grid-cols-3">
            <.input field={@form[:vk_url]} type="text" label={gettext("VK Link")} />
            <.input field={@form[:whatsapp_url]} type="text" label={gettext("WhatsApp Link")} />
            <.input field={@form[:instagram_url]} type="text" label={gettext("Instagram Link")} />
          </div>
        </.section>

        <.section id="branch-map" title={gettext("YCart Settings")}>
          <.inputs_for :let={ycart} field={@form[:ycart_settings]}>
            <.input field={ycart[:enabled]} type="checkbox" label={gettext("YCart Enabled")} />
            <div class="grid gap-4 sm:grid-cols-2">
              <.input field={ycart[:yandex_org_id]} type="text" label={gettext("Yandex Org ID")} />
              <.input field={ycart[:address]} type="text" label={gettext("YCart Address")} />
              <.input
                field={ycart[:latitude]}
                type="number"
                step="0.000001"
                label={gettext("Latitude")}
              />
              <.input
                field={ycart[:longitude]}
                type="number"
                step="0.000001"
                label={gettext("Longitude")}
              />
            </div>
          </.inputs_for>
        </.section>

        <div class="sticky bottom-0 z-10 -mx-1 flex justify-end gap-3 border-t border-base-300 bg-base-200/90 px-1 py-4 backdrop-blur">
          <.link navigate={~p"/staff/branches"} class="btn btn-ghost">{gettext("Cancel")}</.link>
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
