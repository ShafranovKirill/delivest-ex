defmodule DelivestWeb.Hooks.StaffActiveBranch do
  import Phoenix.LiveView
  import Phoenix.Component
  alias Delivest.Identity.Acl
  alias Delivest.Net

  def on_mount(:default, _params, session, socket) do
    current_staff = socket.assigns[:current_staff]
    active_branch_id = session["active_branch_id"]

    cond do
      is_nil(active_branch_id) ->
        case current_staff.branches do
          [branch] ->
            {:halt, redirect(socket, to: "/staff/branches/select/#{branch.id}")}

          _ ->
            {:halt,
             socket
             |> put_flash(
               :info,
               Gettext.dgettext(
                 DelivestWeb.Gettext,
                 "info",
                 "Please select a branch to continue."
               )
             )
             |> redirect(to: "/staff/branches/select")}
        end

      not Acl.has_branch_access?(current_staff, active_branch_id) ->
        {:halt,
         socket
         |> put_flash(
           :error,
           Gettext.dgettext(
             DelivestWeb.Gettext,
             "error",
             "Access to this branch has been revoked."
           )
         )
         |> redirect(to: "/staff/branches/select")}

      true ->
        case Net.get_branch(active_branch_id) do
          {:ok, branch} ->
            socket =
              socket
              |> assign(:active_branch_id, active_branch_id)
              |> assign(:current_branch, branch)
              |> attach_hook(
                :staff_active_branch_reloaded,
                :handle_info,
                &check_branch_access_on_event/2
              )

            {:cont, socket}

          _ ->
            {:halt,
             socket
             |> put_flash(
               :error,
               Gettext.dgettext(DelivestWeb.Gettext, "error", "Branch not found.")
             )
             |> redirect(to: "/staff/branches/select")}
        end
    end
  end

  defp check_branch_access_on_event(event, socket)
       when event in [:staff_updated] do
    current_staff = socket.assigns[:current_staff]
    active_branch_id = socket.assigns[:active_branch_id]

    if current_staff && active_branch_id do
      if Acl.has_branch_access?(current_staff, active_branch_id) do
        {:cont, socket}
      else
        {:halt,
         socket
         |> put_flash(
           :error,
           Gettext.dgettext(
             DelivestWeb.Gettext,
             "error",
             "Access to this branch has been revoked."
           )
         )
         |> redirect(to: "/staff/branches/select")}
      end
    else
      {:cont, socket}
    end
  end

  defp check_branch_access_on_event(_message, socket), do: {:cont, socket}
end
