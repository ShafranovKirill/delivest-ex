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
        case(Identity.get_staff(staff_id, preload: [:role])) do
          {:ok, %{status: :active} = staff} ->
            socket = assign(:current_staff, staff)
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
end
