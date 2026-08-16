defmodule DelivestWeb.Staff.BranchLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.Net.Branches
  alias Delivest.Repo

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff
    branches = Repo.all(Branches.list_branch(staff))

    {:ok,
     socket
     |> assign(:branches, branches)
     |> assign(:modal, nil)
     |> assign(:selected_branch, nil)}
  end

  @impl true
  def handle_event("open_create_modal", _, socket) do
    {:noreply,
     socket
     |> assign(:modal, :create)
     |> assign(:selected_branch, nil)}
  end

  @impl true
  def handle_event("open_edit_modal", %{"id" => id}, socket) do
    case Branches.get_branch(id, preload: [:info]) do
      {:ok, branch} ->
        {:noreply,
         socket
         |> assign(:modal, :edit)
         |> assign(:selected_branch, branch)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Branch not found"))}
    end
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply,
     socket
     |> assign(:modal, nil)
     |> assign(:selected_branch, nil)}
  end

  @impl true
  def handle_event("save_branch", %{"branch" => branch_params}, socket) do
    staff = socket.assigns.current_staff

    case socket.assigns.modal do
      :create ->
        case Branches.create_branch(staff, branch_params) do
          {:ok, _branch} ->
            branches = Repo.all(Branches.list_branch(staff))

            {:noreply,
             socket
             |> put_flash(:info, gettext("Branch successfully created"))
             |> assign(:branches, branches)
             |> assign(:modal, nil)
             |> assign(:selected_branch, nil)}

          {:error, %Ecto.Changeset{} = _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Validation error on creation"))}

          {:error, :forbidden} ->
            {:noreply,
             put_flash(socket, :error, gettext("Insufficient permissions to create a branch"))}
        end

      :edit ->
        branch = socket.assigns.selected_branch
        branch_attrs = Map.take(branch_params, ["name"])
        info_attrs = Map.take(branch_params, ["address", "phone_number"])

        case Branches.update_branch(branch, branch_attrs, info_attrs) do
          {:ok, _updated_branch} ->
            branches = Repo.all(Branches.list_branch(staff))

            {:noreply,
             socket
             |> put_flash(:info, gettext("Branch successfully updated"))
             |> assign(:branches, branches)
             |> assign(:modal, nil)
             |> assign(:selected_branch, nil)}

          {:error, _, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Error updating branch"))}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-6">
      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-3xl font-bold">{gettext("Branches Management")}</h1>
          <p class="text-sm opacity-70">{gettext("List of available company branches")}</p>
        </div>
        <button type="button" class="btn btn-primary" phx-click="open_create_modal">
          {gettext("Create Branch")}
        </button>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <%= for branch <- @branches do %>
          <div
            class="card bg-base-100 shadow-xl cursor-pointer hover:shadow-2xl transition-all"
            phx-click="open_edit_modal"
            phx-value-id={branch.id}
          >
            <div class="card-body">
              <h2 class="card-title">{branch.name}</h2>
              <p class="text-xs opacity-60">{gettext("Click to view and edit")}</p>
            </div>
          </div>
        <% end %>
      </div>

      <%= if @modal do %>
        <div class="modal modal-open">
          <div class="modal-box">
            <h3 class="font-bold text-lg mb-4">
              {if @modal == :create, do: gettext("Create Branch"), else: gettext("Edit Branch")}
            </h3>

            <form phx-submit="save_branch">
              <div class="form-control w-full mb-4">
                <label class="label">
                  <span class="label-text">{gettext("Branch Name")}</span>
                </label>
                <input
                  type="text"
                  name="branch[name]"
                  value={if @modal == :edit, do: @selected_branch.name, else: ""}
                  class="input input-bordered w-full"
                  required
                />
              </div>

              <%= if @modal == :edit do %>
                <div class="form-control w-full mb-4">
                  <label class="label">
                    <span class="label-text">{gettext("Address")}</span>
                  </label>
                  <input
                    type="text"
                    name="branch[address]"
                    value={
                      if Ecto.assoc_loaded?(@selected_branch.info) && @selected_branch.info,
                        do: @selected_branch.info.address,
                        else: ""
                    }
                    class="input input-bordered w-full"
                  />
                </div>

                <div class="form-control w-full mb-4">
                  <label class="label">
                    <span class="label-text">{gettext("Phone Number")}</span>
                  </label>
                  <input
                    type="text"
                    name="branch[phone_number]"
                    value={
                      if Ecto.assoc_loaded?(@selected_branch.info) && @selected_branch.info,
                        do: @selected_branch.info.phone_number,
                        else: ""
                    }
                    class="input input-bordered w-full"
                  />
                </div>
              <% end %>

              <div class="modal-action">
                <button type="button" class="btn" phx-click="close_modal">{gettext("Cancel")}</button>
                <button type="submit" class="btn btn-primary">{gettext("Save")}</button>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
