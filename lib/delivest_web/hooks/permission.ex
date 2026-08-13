defmodule DelivestWeb.Hooks.Permission do
  import Phoenix.LiveView
  import Phoenix.Component

  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Identity

  def on_mount(permission, _params, _session, socket) do
    staff = socket.assigns[:current_staff]

    if Identity.can?(staff, permission) do
      {:cont, assign(socket, :required_permission, permission)}
    else
      {:halt,
       socket
       |> put_flash(
         :error,
         dgettext(
           "errors",
           "You don't have permission to access this page."
         )
       )
       |> redirect(to: "/dashboard")}
    end
  end
end
