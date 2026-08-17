defmodule DelivestWeb.Staff.BranchLive.BranchFormComponent do
  use DelivestWeb, :live_component
  alias DelivestWeb.Staff.BranchLive.BranchForm
  alias Delivest.Net.Branches

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    branch = socket.assigns.branch

    form_data = if branch && branch.id, do: BranchForm.from_branch(branch), else: %BranchForm{}
    changeset = BranchForm.changeset(form_data, %{})

    {:ok, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"branch_form" => params}, socket) do
    base_form =
      if socket.assigns.branch.id,
        do: BranchForm.from_branch(socket.assigns.branch),
        else: %BranchForm{}

    changeset =
      base_form
      |> BranchForm.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"branch_form" => params}, socket) do
    save_branch(socket, socket.assigns.action, params)
  end

  defp save_branch(socket, :edit, params),
    do:
      socket.assigns.branch
      |> BranchForm.from_branch()
      |> BranchForm.changeset(params)
      |> do_save_branch(socket, :edit)

  defp save_branch(socket, :new, params),
    do:
      %BranchForm{}
      |> BranchForm.changeset(params)
      |> do_save_branch(socket, :new)

  defp do_save_branch(%Ecto.Changeset{valid?: true} = changeset, socket, :new) do
    {branch_params, info_params} = BranchForm.to_params(changeset)

    case Branches.create_branch(
           socket.assigns.current_staff,
           branch_params,
           info_params
         ) do
      {:ok, branch} ->
        # Только уведомляем родителя, навигацию делает родительский LiveView!
        notify_parent({:saved, branch})

        {:noreply, socket}

      {:error, _step, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp do_save_branch(%Ecto.Changeset{valid?: true} = changeset, socket, :edit) do
    {branch_params, info_params} = BranchForm.to_params(changeset)

    case Branches.update_branch(
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
          <.input field={@form[:address]} type="text" label={gettext("Address")} />
          <.input field={@form[:phone_number]} type="text" label={gettext("Phone Number")} />
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
