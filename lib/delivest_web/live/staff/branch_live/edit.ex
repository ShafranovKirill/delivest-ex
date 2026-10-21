defmodule DelivestWeb.Staff.BranchLive.Edit do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Identity.Branch
  alias DelivestWeb.Staff.BranchLive.BranchFormComponent

  on_mount {DelivestWeb.Hooks.Permission, "branches.read"}

  @impl true
  def mount(params, _session, socket) do
    case load(socket.assigns.live_action, params, socket.assigns.current_staff) do
      {:ok, branch, title} ->
        {:ok, assign(socket, branch: branch, page_title: title)}

      {:error, message} ->
        {:ok, socket |> put_flash(:error, message) |> push_navigate(to: ~p"/staff/branches")}
    end
  end

  defp load(:new, _params, staff) do
    if Identity.can?(staff, "branches.create"),
      do: {:ok, %Branch{}, gettext("Create branch")},
      else: {:error, gettext("You don't have permission to create branch.")}
  end

  defp load(:edit, %{"slug" => slug}, staff) do
    with true <- Identity.can?(staff, "branches.update"),
         %Branch{} = branch <-
           Enum.find(Identity.list_branch_for_staff(staff), &(&1.slug == slug)),
         {:ok, branch} <- Identity.get_branch(branch.id, preload: [:info]) do
      {:ok, branch, branch.name}
    else
      false -> {:error, gettext("You don't have permission to edit branches.")}
      _ -> {:error, gettext("Branch not found.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl space-y-6 p-6">
      <div class="flex flex-wrap items-center gap-4">
        <.link navigate={~p"/staff/branches"} class="btn btn-ghost btn-sm btn-square">
          <.icon name="hero-arrow-left" class="size-5" />
        </.link>
        <div class="min-w-0 flex-1">
          <p class="text-xs uppercase tracking-wider text-base-content/50">{gettext("Branches")}</p>
          <h1 class="truncate text-2xl sm:text-3xl font-bold">{@page_title}</h1>
        </div>
        <span :if={@branch.id && !@branch.is_active} class="badge badge-error badge-soft">
          {gettext("Branch is not active")}
        </span>
      </div>

      <.live_component
        module={BranchFormComponent}
        id={@branch.id || :new}
        action={@live_action}
        branch={@branch}
        current_staff={@current_staff}
      />
    </div>
    """
  end
end
