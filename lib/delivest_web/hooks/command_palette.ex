defmodule DelivestWeb.Hooks.CommandPalette do
  import Phoenix.Component
  import Phoenix.LiveView

  alias DelivestWeb.CommandSearch

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> search("")
     |> attach_hook(:command_palette, :handle_event, &handle_event/3)}
  end

  defp handle_event("command_search", %{"query" => query}, socket),
    do: {:halt, search(socket, query)}

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp search(socket, query) do
    %{current_staff: staff} = socket.assigns

    assign(socket,
      command_query: query,
      command_groups: CommandSearch.run(staff, socket.assigns[:current_branch], query)
    )
  end
end
