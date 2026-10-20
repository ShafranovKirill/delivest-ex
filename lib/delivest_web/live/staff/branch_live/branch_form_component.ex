defmodule DelivestWeb.Staff.BranchLive.BranchFormComponent do
  alias Delivest.Identity
  use DelivestWeb, :live_component
  alias Delivest.Integrations.Crm
  alias DelivestWeb.Staff.BranchLive.{BranchForm, WorkingHoursComponent}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    branch = socket.assigns.branch

    changeset = BranchForm.changeset(BranchForm.for_branch(branch), %{})

    {:ok,
     socket
     |> assign(:form, to_form(changeset))
     |> assign_new(:show_crm, fn -> false end)
     |> assign_new(:show_links, fn -> false end)
     |> assign_new(:show_schedule, fn -> false end)
     |> assign_new(:show_ycart, fn -> false end)}
  end

  @impl true
  def handle_event("validate", %{"branch_form" => params}, socket) do
    base_form = BranchForm.for_branch(socket.assigns.branch)

    current_working_hours =
      Ecto.Changeset.get_field(socket.assigns.form.source, :working_hours) || %{}

    new_working_hours =
      Map.merge(
        current_working_hours,
        get_in(params, ["working_hours"]) || %{}
      )

    merged_params = Map.put(params, "working_hours", new_working_hours)

    changeset =
      base_form
      |> BranchForm.changeset(merged_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("toggle_section", %{"section" => section}, socket) do
    key =
      case section do
        "crm" -> :show_crm
        "links" -> :show_links
        "schedule" -> :show_schedule
        "ycart" -> :show_ycart
        _ -> nil
      end

    {:noreply, assign(socket, key, !socket.assigns[key])}
  end

  def handle_event("save", %{"branch_form" => params}, socket) do
    save_branch(socket, socket.assigns.action, params)
  end

  def handle_info({WorkingHoursComponent, {:working_hours_changed, working_hours}}, socket) do
    base_form = BranchForm.for_branch(socket.assigns.branch)

    params = %{"working_hours" => working_hours}

    changeset =
      base_form
      |> BranchForm.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset), working_hours: working_hours)}
  end

  defp save_branch(socket, :edit, params),
    do:
      socket.assigns.branch
      |> BranchForm.from_branch()
      |> BranchForm.changeset(params)
      |> do_save_branch(socket, :edit)

  defp save_branch(socket, :new, params),
    do:
      BranchForm.new()
      |> BranchForm.changeset(params)
      |> do_save_branch(socket, :new)

  defp do_save_branch(%Ecto.Changeset{valid?: true} = changeset, socket, :new) do
    {branch_params, info_params} = BranchForm.to_params(changeset)

    case Identity.create_branch(
           socket.assigns.current_staff,
           branch_params,
           info_params
         ) do
      {:ok, branch} ->
        notify_parent({:saved, branch})
        {:noreply, socket}

      {:error, _step, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp do_save_branch(%Ecto.Changeset{valid?: true} = changeset, socket, :edit) do
    {branch_params, info_params} = BranchForm.to_params(changeset)

    case Identity.update_branch(
           socket.assigns.current_staff,
           socket.assigns.branch,
           branch_params,
           info_params
         ) do
      {:ok, branch} ->
        notify_parent({:saved, branch})
        {:noreply, socket}

      {:error, _step, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp do_save_branch(%Ecto.Changeset{valid?: false} = changeset, socket, _),
    do: {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :insert)))}

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <.form
        for={@form}
        id="branch-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col h-full"
      >
        <div class="flex-1 overflow-y-auto p-6 space-y-6">
          <.input field={@form[:name]} type="text" label={gettext("Branch Name")} required />
          <.input field={@form[:slug]} type="text" label={gettext("Branch Slug")} required />
          <.input field={@form[:address]} type="text" label={gettext("Address")} />
          <.input
            field={@form[:delivery_time]}
            type="number"
            label={gettext("Delivery Time (minutes)")}
          />
          <.input field={@form[:phone_number]} type="text" label={gettext("Phone Number")} />

          <div class="border border-base-300 rounded-box bg-base-100">
            <div
              class="flex justify-between items-center p-4 cursor-pointer select-none font-medium"
              phx-click="toggle_section"
              phx-value-section="schedule"
              phx-target={@myself}
            >
              <span>{gettext("Working Hours")}</span>
              <span class={"transition-transform duration-200 #{if @show_schedule, do: "rotate-180", else: ""}"}>
                ▼
              </span>
            </div>
            <%= if @show_schedule do %>
              <.live_component
                module={WorkingHoursComponent}
                id="working-hours-editor"
                working_hours={Ecto.Changeset.get_field(@form.source, :working_hours) || %{}}
              />
            <% end %>
          </div>

          <div class="border border-base-300 rounded-box bg-base-100">
            <div
              class="flex justify-between items-center p-4 cursor-pointer select-none font-medium"
              phx-click="toggle_section"
              phx-value-section="links"
              phx-target={@myself}
            >
              <span>{gettext("Social Links & Messengers")}</span>
              <span class={"transition-transform duration-200 #{if @show_links, do: "rotate-180", else: ""}"}>
                ▼
              </span>
            </div>
            <%= if @show_links do %>
              <div class="p-4 pt-0 space-y-4 border-t border-base-200">
                <.input field={@form[:vk_url]} type="text" label={gettext("VK Link")} />
                <.input field={@form[:whatsapp_url]} type="text" label={gettext("WhatsApp Link")} />
                <.input field={@form[:instagram_url]} type="text" label={gettext("Instagram Link")} />
              </div>
            <% end %>
          </div>

          <div class="border border-base-300 rounded-box bg-base-100">
            <div
              class="flex justify-between items-center p-4 cursor-pointer select-none font-medium"
              phx-click="toggle_section"
              phx-value-section="ycart"
              phx-target={@myself}
            >
              <span>{gettext("YCart Settings")}</span>
              <span class={"transition-transform duration-200 #{if @show_ycart, do: "rotate-180", else: ""}"}>
                ▼
              </span>
            </div>
            <%= if @show_ycart do %>
              <div class="p-4 pt-0 space-y-4 border-t border-base-200">
                <.inputs_for :let={f_settings} field={@form[:ycart_settings]}>
                  <.input
                    field={f_settings[:enabled]}
                    type="checkbox"
                    label={gettext("YCart Enabled")}
                  />
                  <.input
                    field={f_settings[:yandex_org_id]}
                    type="text"
                    label={gettext("Yandex Org ID")}
                  />
                  <.input
                    field={f_settings[:latitude]}
                    type="number"
                    step="0.000001"
                    label={gettext("Latitude")}
                  />
                  <.input
                    field={f_settings[:longitude]}
                    type="number"
                    step="0.000001"
                    label={gettext("Longitude")}
                  />
                  <.input
                    field={f_settings[:address]}
                    type="text"
                    label={gettext("YCart Address")}
                  />
                </.inputs_for>
              </div>
            <% end %>
          </div>

          <div class="border border-base-300 rounded-box bg-base-100">
            <div
              class="flex justify-between items-center p-4 cursor-pointer select-none font-medium"
              phx-click="toggle_section"
              phx-value-section="crm"
              phx-target={@myself}
            >
              <span>{gettext("CRM Integration")}</span>
              <span class={"transition-transform duration-200 #{if @show_crm, do: "rotate-180", else: ""}"}>
                ▼
              </span>
            </div>
            <div :if={@show_crm} class="p-4 pt-0 space-y-4 border-t border-base-200">
              <.inputs_for :let={crm} field={@form[:crm]}>
                <.input field={crm[:enabled]} type="checkbox" label={gettext("Send orders to CRM")} />
                <.input
                  field={crm[:provider]}
                  type="select"
                  label={gettext("CRM")}
                  prompt={gettext("Choose CRM")}
                  options={Enum.map(Crm.providers(), fn {value, label} -> {label, value} end)}
                />

                <.inputs_for
                  :let={frontpad}
                  :if={to_string(crm[:provider].value) == "frontpad"}
                  field={crm[:frontpad]}
                >
                  <.input
                    field={frontpad[:api_key]}
                    type="password"
                    value={frontpad[:api_key].value}
                    label={gettext("Frontpad API Key")}
                  />
                  <.input
                    field={frontpad[:affiliate]}
                    type="text"
                    label={gettext("Frontpad Branch ID")}
                  />
                </.inputs_for>
              </.inputs_for>
            </div>
          </div>

          <.input field={@form[:is_active]} type="checkbox" label={gettext("Active")} />
        </div>

        <div class="shrink-0 p-6 border-t border-base-200 bg-base-100 flex justify-end gap-3">
          <.link patch={@patch} class="btn btn-ghost">{gettext("Cancel")}</.link>
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
