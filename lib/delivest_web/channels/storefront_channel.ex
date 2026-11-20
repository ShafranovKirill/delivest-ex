defmodule DelivestWeb.StorefrontChannel do
  use DelivestWeb, :channel

  alias Delivest.Storefront

  @heartbeat_ms 15_000

  @impl true
  def join("storefront:" <> branch_id, _params, socket) do
    case Storefront.manifest(branch_id) do
      {:ok, _manifest} ->
        Phoenix.PubSub.subscribe(Delivest.PubSub, "storefront:*")
        Phoenix.PubSub.subscribe(Delivest.PubSub, "storefront:#{branch_id}")
        send(self(), :watermark)
        {:ok, assign(socket, branch_id: branch_id)}

      _ ->
        {:error, %{code: "branch_not_found"}}
    end
  end

  @impl true
  def handle_info(:watermark, socket) do
    case Storefront.watermark(socket.assigns.branch_id) do
      {:ok, payload} ->
        push(socket, "watermark", payload)
        Process.send_after(self(), :watermark, @heartbeat_ms)
        {:noreply, socket}

      _ ->
        push(socket, "revision", %{
          section: "branches",
          invalid: true,
          valid_until: DateTime.utc_now()
        })

        {:stop, :normal, socket}
    end
  end

  def handle_info(%{section: section}, socket) do
    case Storefront.watermark(socket.assigns.branch_id) do
      {:ok, payload} ->
        push(socket, "revision", Map.put(payload, :section, section))
        {:noreply, socket}

      _ ->
        push(socket, "revision", %{
          section: "branches",
          invalid: true,
          valid_until: DateTime.utc_now()
        })

        {:stop, :normal, socket}
    end
  end
end
