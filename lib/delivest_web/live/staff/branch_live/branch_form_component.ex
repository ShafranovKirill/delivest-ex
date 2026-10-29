defmodule DelivestWeb.Staff.BranchLive.BranchFormComponent do
  use DelivestWeb, :live_component

  import DelivestWeb.Staff.BranchLive.LocationFields

  alias Delivest.Identity
  alias Delivest.Integrations.Dadata
  alias DelivestWeb.Staff.BranchLive.{BranchForm, Location, WorkingHoursComponent}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    changeset = BranchForm.changeset(BranchForm.for_branch(socket.assigns.branch), %{})

    {:ok,
     assign(socket,
       form: to_form(changeset),
       address_map: Dadata.active?(),
       location_suggestions: []
     )}
  end

  @impl true
  def handle_event("validate", %{"_target" => ["location_query"]} = params, socket) do
    {:noreply, assign(socket, location_suggestions: Location.suggest(params["location_query"]))}
  end

  def handle_event("validate", %{"branch_form" => params}, socket) do
    changeset =
      socket.assigns.branch
      |> BranchForm.for_branch()
      |> BranchForm.changeset(with_working_hours(params, socket))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("pick_location", %{"index" => index}, socket) do
    case Enum.at(socket.assigns.location_suggestions, String.to_integer(index)) do
      nil ->
        {:noreply, socket}

      address ->
        changes = Location.changes(address)

        {:noreply,
         socket
         |> put_location(changes)
         |> assign(location_suggestions: [])
         |> center_map(changes)}
    end
  end

  def handle_event("location_moved", %{"lat" => lat, "lng" => lng}, socket) do
    {:noreply, put_location(socket, Location.at(lat / 1, lng / 1))}
  end

  def handle_event("save", %{"branch_form" => params}, socket) do
    socket.assigns.branch
    |> BranchForm.for_branch()
    |> BranchForm.changeset(with_working_hours(params, socket))
    |> save(socket)
  end

  defp put_location(socket, changes) do
    assign(socket, form: to_form(Ecto.Changeset.change(socket.assigns.form.source, changes)))
  end

  defp center_map(socket, %{latitude: lat, longitude: lng}) when is_float(lat) and is_float(lng),
    do: push_event(socket, "location:center", %{lat: lat, lng: lng})

  defp center_map(socket, _changes), do: socket

  defp with_working_hours(params, socket) do
    current = Ecto.Changeset.get_field(socket.assigns.form.source, :working_hours) || %{}
    Map.put(params, "working_hours", Map.merge(current, params["working_hours"] || %{}))
  end

  defp save(%Ecto.Changeset{valid?: false} = changeset, socket),
    do: {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :insert)))}

  defp save(changeset, socket) do
    {branch_params, info_params} = BranchForm.to_params(changeset)

    case persist(socket.assigns, branch_params, info_params) do
      {:ok, branch} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Branch saved successfully"))
         |> push_navigate(to: sections_path(branch))}

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

  defp persist(%{current_staff: staff, branch: branch}, branch_params, info_params),
    do: Identity.update_branch(staff, branch, branch_params, info_params)

  defp copy_errors(changeset, error) do
    error.errors
    |> Enum.reduce(changeset, fn {field, {message, opts}}, acc ->
      Ecto.Changeset.add_error(acc, field, message, opts)
    end)
    |> Map.put(:action, :insert)
  end

  defp sections_path(branch), do: ~p"/staff/branches/#{branch.slug}/edit"

  defp cancel_path(%{action: :new}), do: ~p"/staff/branches"
  defp cancel_path(%{branch: branch}), do: sections_path(branch)

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={@form}
        id="branch-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <section class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6">
          <p :if={@section.description} class="text-sm text-base-content/60">
            {@section.description}
          </p>

          <div :if={@section.id == :general} class="space-y-4">
            <div class="grid gap-4 sm:grid-cols-2">
              <.input field={@form[:name]} type="text" label={gettext("Branch Name")} required />
              <.input field={@form[:slug]} type="text" label={gettext("Branch Slug")} required />
              <.input
                field={@form[:code]}
                type="text"
                label={gettext("Branch code")}
                placeholder={gettext("MSK1")}
                maxlength="6"
                class="input w-full uppercase"
              />
              <.input field={@form[:phone_number]} type="text" label={gettext("Phone Number")} />
              <.input
                field={@form[:delivery_time]}
                type="number"
                label={gettext("Delivery Time (minutes)")}
              />
            </div>
            <.input field={@form[:is_active]} type="checkbox" label={gettext("Active")} />
          </div>

          <.location_fields
            :if={@section.id == :location}
            form={@form}
            map={@address_map}
            suggestions={@location_suggestions}
            target={@myself}
          />

          <.live_component
            :if={@section.id == :hours}
            module={WorkingHoursComponent}
            id="working-hours-editor"
            working_hours={Ecto.Changeset.get_field(@form.source, :working_hours) || %{}}
          />

          <.inputs_for :let={kitchen} :if={@section.id == :kitchen} field={@form[:kitchen]}>
            <.input field={kitchen[:enabled]} type="checkbox" label={gettext("Kitchen works")} />
            <div class="grid gap-4 sm:grid-cols-2">
              <.input
                field={kitchen[:lead_minutes]}
                type="number"
                min="0"
                label={gettext("Send to the kitchen, minutes before the time")}
              />
            </div>
          </.inputs_for>

          <div :if={@section.id == :links} class="grid gap-4 sm:grid-cols-3">
            <.input field={@form[:vk_url]} type="text" label={gettext("VK Link")} />
            <.input field={@form[:whatsapp_url]} type="text" label={gettext("WhatsApp Link")} />
            <.input field={@form[:instagram_url]} type="text" label={gettext("Instagram Link")} />
          </div>

          <.inputs_for :let={ycart} :if={@section.id == :ycart} field={@form[:ycart_settings]}>
            <.input field={ycart[:enabled]} type="checkbox" label={gettext("YCart Enabled")} />
            <div class="grid gap-4 sm:grid-cols-2">
              <.input field={ycart[:yandex_org_id]} type="text" label={gettext("Yandex Org ID")} />
            </div>
          </.inputs_for>
        </section>

        <div class="flex justify-end gap-3">
          <.link navigate={cancel_path(assigns)} class="btn btn-ghost">{gettext("Cancel")}</.link>
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
