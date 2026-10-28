defmodule DelivestWeb.Hooks.StaffActiveBranch do
  import Phoenix.LiveView
  import Phoenix.Component
  use Gettext, backend: DelivestWeb.Gettext
  alias Delivest.Identity

  def on_mount(:optional, _params, session, socket) do
    case accessible(socket.assigns[:current_staff], session["active_branch_id"]) do
      {:ok, branch} ->
        {:cont, socket |> assign(:active_branch_id, branch.id) |> assign(:current_branch, branch)}

      :error ->
        {:cont, socket}
    end
  end

  def on_mount(:default, %{"branch_slug" => slug}, _session, socket) do
    staff = socket.assigns[:current_staff]

    with {:ok, branch} <- Identity.get_branch_by_slug(slug),
         true <- Identity.has_branch_access?(staff, branch.id) do
      {:cont,
       socket
       |> assign(:active_branch_id, branch.id)
       |> assign(:current_branch, branch)
       |> attach_hook(
         :staff_active_branch_reloaded,
         :handle_info,
         &check_branch_access_on_event/2
       )}
    else
      _ -> {:halt, to_select(socket, dgettext("errors", "Branch not found or access denied."))}
    end
  end

  def accessible(staff, branch_id) when is_binary(branch_id) do
    with true <- Identity.has_branch_access?(staff, branch_id),
         {:ok, branch} <- Identity.get_branch(branch_id) do
      {:ok, branch}
    else
      _ -> :error
    end
  end

  def accessible(_staff, _branch_id), do: :error

  defp check_branch_access_on_event(:staff_updated, socket) do
    if Identity.has_branch_access?(socket.assigns.current_staff, socket.assigns.active_branch_id),
      do: {:cont, socket},
      else:
        {:halt, to_select(socket, dgettext("errors", "Access to this branch has been revoked."))}
  end

  defp check_branch_access_on_event(_message, socket), do: {:cont, socket}

  defp to_select(socket, message) do
    socket
    |> put_flash(:error, message)
    |> redirect(to: "/staff/branches/select")
  end
end
