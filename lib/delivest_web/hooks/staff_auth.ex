defmodule DelivestWeb.Hooks.StaffAuth do
  import Phoenix.LiveView
  import Phoenix.Component
  alias Delivest.Identity

  def on_mount(:default, _params, session, socket) do
    locale = DelivestWeb.Plugs.Locale.restore_from_session(session)

    socket = assign(socket, :locale, locale)

    case session["staff_id"] do
      nil ->
        {:cont, assign(socket, :current_staff, nil)}

      staff_id ->
        case(Identity.get_staff(staff_id, preload: [:role, :branches])) do
          {:ok, staff} ->
            maybe_connect_auth_events(socket, staff)

            socket =
              socket
              |> assign(:current_staff, staff)
              |> attach_hook(:current_staff_reloaded, :handle_info, &reload_user_on_event/2)

            {:cont, socket}

          _ ->
            {:cont, assign(socket, :current_staff, nil)}
        end
    end
  end

  def on_mount(:require_authenticated_staff, _params, _session, socket) do
    if socket.assigns[:current_staff] do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/staff/auth/login")}
    end
  end

  def maybe_connect_auth_events(socket, staff) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Delivest.PubSub, "staff_updates:#{staff.id}")
      Phoenix.PubSub.subscribe(Delivest.PubSub, "role_updates:#{staff.role_id}")
    end
  end

  defp reload_user_on_event(event, socket) when event in [:role_updated, :staff_updated] do
    case Identity.get_staff(socket.assigns.current_staff.id, preload: [:role, :branches]) do
      {:ok, fresh_staff} ->
        socket = assign(socket, :current_staff, fresh_staff)

        required_perm = socket.assigns[:required_permission]

        if required_perm && not Identity.can?(fresh_staff, required_perm) do
          {:halt,
           socket
           |> put_flash(
             :error,
             Gettext.dgettext(
               DelivestWeb.Gettext,
               "errors",
               "You dont have permission to access this page"
             )
           )
           |> redirect(to: "/staff/dashboard")}
        else
          {:cont, socket}
        end

      {:error, :not_found} ->
        {:halt, push_event(socket, "force_staff_logout", %{})}
    end
  end

  defp reload_user_on_event(_message, socket), do: {:cont, socket}
end
