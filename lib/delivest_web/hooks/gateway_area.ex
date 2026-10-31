defmodule DelivestWeb.Hooks.GatewayArea do
  import Phoenix.Component

  alias Delivest.Gateway

  def on_mount(area, _params, _session, socket) do
    branch = socket.assigns[:current_branch]

    if branch && Gateway.crm?(branch, area) do
      {:cont, assign(socket, :gateway_block, %{area: area, name: Gateway.mode(branch).name})}
    else
      {:cont, socket}
    end
  end
end
