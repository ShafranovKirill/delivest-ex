defmodule DelivestWeb.Staff.BranchLive.Branches do
  use DelivestWeb, :live_view

  alias Delivest.Net
  alias Delivest.Repo
  alias Delivest.Net.Branch
  alias Delivest.Identity

  on_mount {DelivestWeb.Hooks.Permission, "branches.read"}

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff

    branches =
      staff
      |> Net.list_branch()
      |> Repo.all()
      |> Repo.preload(:info)

    {:ok, assign(socket, branches: branches, branch_to_delete: nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, page_title: gettext("Branches"), branch: nil)
  end

  defp apply_action(socket, :new, _params) do
    if Identity.can?(socket.assigns.current_staff, "branches.create") do
      assign(socket, page_title: gettext("Create branch"), branch: %Branch{})
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to create branch."))
      |> push_patch(to: ~p"/staff/branches")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    if Identity.can?(socket.assigns.current_staff, "branches.update") do
      case Net.get_branch(id, preload: [:info]) do
        {:ok, branch} ->
          assign(socket, page_title: gettext("Edit Branch"), branch: branch)

        _ ->
          socket
          |> put_flash(:error, gettext("Branch not found."))
          |> push_patch(to: ~p"/staff/branches")
      end
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to edit branches."))
      |> push_patch(to: ~p"/staff/branches")
    end
  end

  @impl true
  def handle_info({DelivestWeb.Staff.BranchLive.BranchFormComponent, {:saved, branch}}, socket) do
    branch = Repo.preload(branch, :info)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Branch saved successfully"))
     |> push_patch(to: ~p"/staff/branches")
     |> update(:branches, fn branches ->
       if Enum.any?(branches, &(&1.id == branch.id)) do
         Enum.map(branches, fn b -> if b.id == branch.id, do: branch, else: b end)
       else
         [branch | branches]
       end
     end)}
  end

  @impl true
  def handle_event("delete_branch", %{"id" => id}, socket) do
    case Net.get_branch(id) do
      {:ok, branch} ->
        {:noreply, assign(socket, branch_to_delete: branch)}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Branch not found."))}
    end
  end

  @impl true
  def handle_event(
        "confirm_delete",
        _,
        %{assigns: %{branch_to_delete: branch, current_staff: staff} = _assigns} = socket
      ) do
    case Net.soft_delete_branch(staff, branch) do
      {:ok, deleted_branch} ->
        branches = Enum.reject(socket.assigns.branches, &(&1.id == deleted_branch.id))

        {:noreply,
         socket
         |> put_flash(:info, gettext("Branch deleted successfully"))
         |> assign(branches: branches, branch_to_delete: nil)}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("You don't have permission to delete branches."))
         |> assign(branch_to_delete: nil)}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Failed to delete branch"))
         |> assign(branch_to_delete: nil)}
    end
  end

  @impl true
  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, branch_to_delete: nil)}
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

        <.link patch={~p"/staff/branches/new"} class="btn btn-primary">
          {gettext("Create Branch")}
        </.link>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <%= for branch <- @branches do %>
          <div class="card bg-base-100 shadow-xl hover:shadow-2xl transition-all">
            <div class="card-body flex flex-row items-start justify-between gap-4">
              <.link
                patch={~p"/staff/branches/#{branch.id}/edit"}
                class="cursor-pointer flex-1"
              >
                <h2 class="card-title">{branch.name}</h2>
                <p class="text-xs opacity-60 mt-4">{gettext("Click to view and edit")}</p>
              </.link>

              <div class="flex flex-col items-center gap-1 shrink-0">
                <.link
                  patch={~p"/staff/branches/#{branch.id}/edit"}
                  class="btn btn-sm btn-ghost btn-square text-info"
                  title={gettext("Edit")}
                >
                  <.icon name="hero-pencil-square" class="w-5 h-5" />
                </.link>

                <button
                  type="button"
                  phx-click="delete_branch"
                  phx-value-id={branch.id}
                  class="btn btn-sm btn-ghost btn-square text-error"
                  title={gettext("Delete")}
                >
                  <.icon name="hero-trash" class="w-5 h-5" />
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <.modal
        id="delete-branch-modal"
        show={@branch_to_delete != nil}
        title={gettext("Delete Branch")}
        description={gettext("Are you sure you want to delete this branch?")}
        confirm_label={gettext("Delete")}
        danger={true}
        on_cancel={JS.push("cancel_delete")}
        on_confirm={JS.push("confirm_delete")}
      />

      <.slide_over
        id="branch-slideover"
        show={@live_action in [:new, :edit]}
        title={@page_title}
        on_close={JS.patch(~p"/staff/branches")}
      >
        <.live_component
          :if={@branch}
          module={DelivestWeb.Staff.BranchLive.BranchFormComponent}
          id={@branch.id || :new}
          action={@live_action}
          branch={@branch}
          current_staff={@current_staff}
          patch={~p"/staff/branches"}
        />
      </.slide_over>
    </div>
    """
  end
end
