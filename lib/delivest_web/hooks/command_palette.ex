defmodule DelivestWeb.Hooks.CommandPalette do
  import Phoenix.Component
  import Phoenix.LiveView

  alias DelivestWeb.{CommandSearch, StaffHeader}

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> search("")
     |> attach_hook(:command_palette, :handle_event, &handle_event/3)
     |> attach_hook(:command_palette_refresh, :handle_info, fn
       :features_changed, socket -> {:cont, search(socket, socket.assigns[:command_query] || "")}
       _, socket -> {:cont, socket}
     end)}
  end

  defp handle_event("command_search", %{"query" => query}, socket),
    do: {:halt, search(socket, query)}

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp search(socket, query) do
    %{current_staff: staff} = socket.assigns

    actual_branch = StaffHeader.scope_branch_from_assigns(socket.assigns)
    navigation_branch = StaffHeader.navigation_branch_from_assigns(socket.assigns)

    assign(socket,
      command_query: query,
      command_groups:
        CommandSearch.run(staff, actual_branch, query, navigation_branch: navigation_branch)
    )
  end
end
