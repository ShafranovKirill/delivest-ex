defmodule DelivestWeb.Staff.StaffLive.StaffFormComponent do
  use DelivestWeb, :live_component

  alias Delivest.{Identity}
  alias Delivest.Identity.Staff

  import Ecto.Changeset

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    current_staff_id = socket.assigns[:staff] && socket.assigns[:staff].id
    new_staff_id = assigns.staff && assigns.staff.id

    if is_nil(socket.assigns[:form]) || current_staff_id != new_staff_id ||
         socket.assigns[:action] != assigns.action do
      staff = assigns.staff
      current_staff = assigns.current_staff

      form_data = if staff && staff.id, do: staff, else: %Staff{}

      initial_params =
        if staff && staff.id && Ecto.assoc_loaded?(staff.branches) do
          %{"branch_ids" => Enum.map(staff.branches, & &1.id)}
        else
          %{}
        end

      changeset = Staff.changeset(form_data, initial_params)

      role_options =
        Identity.list_all_roles(current_staff)
        |> Enum.map(&{&1.name, &1.id})

      branch_options =
        Identity.list_branch_for_staff(current_staff)
        |> Enum.map(&{&1.name, &1.id})

      {:ok,
       socket
       |> assign(:form, to_form(changeset))
       |> assign(:role_options, role_options)
       |> assign(:branch_options, branch_options)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("validate", %{"staff" => params}, socket) do
    params =
      Map.update(params, "branch_ids", [], fn
        val when is_binary(val) -> []
        val -> val
      end)

    base_form =
      if socket.assigns.staff.id,
        do: socket.assigns.staff,
        else: %Staff{}

    changeset =
      base_form
      |> Staff.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"staff" => params}, socket) do
    save_staff(socket, socket.assigns.action, params)
  end

  defp save_staff(socket, :edit, params),
    do:
      socket.assigns.staff
      |> Staff.changeset(params)
      |> Map.put(:action, :update)
      |> do_save_staff(socket, :edit)

  defp save_staff(socket, :new, params),
    do:
      %Staff{}
      |> Staff.changeset(params)
      |> Map.put(:action, :insert)
      |> do_save_staff(socket, :new)

  defp do_save_staff(%Ecto.Changeset{valid?: true} = changeset, socket, :edit) do
    case Identity.update_staff(
           socket.assigns.current_staff,
           socket.assigns.staff,
           to_params(changeset)
         ) do
      {:ok, staff} ->
        notify_parent({:saved, staff})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp do_save_staff(%Ecto.Changeset{valid?: true} = changeset, socket, :new) do
    case Identity.create_staff(socket.assigns.current_staff, to_params(changeset)) do
      {:ok, staff} ->
        notify_parent({:saved, staff})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp do_save_staff(%Ecto.Changeset{valid?: false} = changeset, socket, _action) do
    {:noreply, assign(socket, form: to_form(changeset))}
  end

  defp to_params(changeset) do
    data = apply_changes(changeset)

    data
    |> Map.take([:login, :password, :name, :role_id, :branch_ids])
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <.form
        for={@form}
        id="account-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col h-full"
      >
        <div class="flex-1 overflow-y-auto p-6 space-y-6">
          <div class="divider text-xs font-bold uppercase text-base-content/50">
            {gettext("Staff Account")}
          </div>

          <.input field={@form[:login]} type="text" label={gettext("Login")} required />

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input
              field={@form[:password]}
              type="password"
              label={gettext("Password")}
              required={is_nil(@staff.id)}
              autocomplete="new-password"
              placeholder={
                if @staff.id,
                  do: gettext("Enter to edit"),
                  else: gettext("Enter password")
              }
            />
            <.input
              :if={not is_nil(@form[:password].value) && @form[:password].value != ""}
              field={@form[:password_confirmation]}
              type="password"
              label={gettext("Repeat Password")}
              required={is_nil(@staff.id)}
              autocomplete="new-password"
              placeholder={gettext("Repeat password")}
            />
          </div>
          <.input field={@form[:name]} type="text" label={gettext("Name")} required />

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input
              field={@form[:role_id]}
              type="select"
              label={gettext("Role")}
              options={@role_options}
              required
              autocomplete="new-password"
              prompt={gettext("Select a role...")}
            />
          </div>

          <div class="divider text-xs font-bold uppercase text-base-content/50">
            {gettext("Branches Access")}
          </div>

          <div class="space-y-2">
            <div class="flex items-center justify-between">
              <label class="label">
                <span class="label-text font-bold">{gettext("Branches")}</span>
              </label>
              <span class="text-xs text-base-content/60">
                <% branch_ids = List.wrap(@form[:branch_ids].value) %>
                {length(branch_ids)} {gettext("selected")}
              </span>
            </div>

            <input type="hidden" name={@form[:branch_ids].name} value="" />

            <div class="grid grid-cols-1 gap-2 max-h-52 overflow-y-auto p-3 border border-base-200 rounded-box bg-base-100 shadow-inner">
              <%= for {name, id} <- @branch_options do %>
                <% current_values = @form[:branch_ids].value || [] %>
                <% checked =
                  id in current_values or to_string(id) in Enum.map(current_values, &to_string/1) %>

                <label class={[
                  "label cursor-pointer justify-start gap-3 p-2.5 rounded-lg transition-all border",
                  checked && "bg-primary/5 border-primary/20",
                  !checked && "border-transparent hover:bg-base-200/50"
                ]}>
                  <input
                    type="checkbox"
                    name={@form[:branch_ids].name <> "[]"}
                    value={id}
                    checked={checked}
                    class="checkbox checkbox-primary checkbox-sm"
                  />
                  <span class="label-text text-sm font-medium">{name}</span>
                </label>
              <% end %>
            </div>
          </div>
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
