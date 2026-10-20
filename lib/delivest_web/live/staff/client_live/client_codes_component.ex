defmodule DelivestWeb.Staff.ClientLive.ClientCodesComponent do
  use DelivestWeb, :live_component

  alias Delivest.Promo
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(promotions: Promo.list_personal_promotions(assigns.branch_id), issued: nil)
     |> load_codes()}
  end

  @impl true
  def handle_event("issue", %{"issue" => %{"promotion_id" => id} = params}, socket) do
    %{current_staff: staff, branch_id: branch_id, client: client} = socket.assigns

    with {:ok, promotion} <- Promo.get_promotion(staff, branch_id, id),
         {:ok, code} <- Promo.issue_code(staff, promotion, client, uses(params["uses"])) do
      {:noreply, socket |> assign(issued: code) |> load_codes()}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Failed to issue a code"))}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    with {:ok, code} <- Promo.get_issued_code(socket.assigns.branch_id, id),
         {:ok, _code} <- Promo.revoke_code(socket.assigns.current_staff, code) do
      {:noreply, load_codes(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  defp load_codes(socket),
    do:
      assign(socket,
        codes: Promo.list_client_codes(socket.assigns.client.id, socket.assigns.branch_id)
      )

  defp uses(value) do
    case Integer.parse(to_string(value)) do
      {uses, ""} when uses > 0 -> uses
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-box border border-base-200 shadow-sm p-4 space-y-3">
      <h2 class="font-bold">{gettext("Personal promo codes")}</h2>

      <p :if={@promotions == []} class="text-sm text-base-content/60">
        {gettext("Create a promotion with personal codes in this branch first.")}
      </p>

      <form
        :if={@promotions != []}
        id="client-issue-code"
        phx-submit="issue"
        phx-target={@myself}
        class="space-y-2"
      >
        <select name="issue[promotion_id]" class="select select-sm w-full">
          <option :for={promotion <- @promotions} value={promotion.id}>{promotion.name}</option>
        </select>
        <div class="join w-full">
          <input
            type="number"
            min="1"
            name="issue[uses]"
            value="1"
            class="input input-sm join-item w-20"
            title={gettext("Uses")}
          />
          <button type="submit" class="btn btn-sm btn-primary join-item flex-1">
            <.icon name="hero-ticket" class="size-4" /> {gettext("Issue code")}
          </button>
        </div>
      </form>

      <div :if={@issued} class="alert alert-success text-sm py-2">
        <span class="font-mono font-bold text-base select-all">{@issued.code}</span>
      </div>

      <ul :if={@codes != []} class="divide-y divide-base-200 text-sm">
        <li :for={code <- @codes} class="py-2 flex items-center gap-2">
          <div class="flex-1 min-w-0">
            <p class="font-mono font-bold">{code.code}</p>
            <p class="text-xs text-base-content/60 truncate">
              {code.promotion.name} · {OrderHelpers.local_datetime(code.inserted_at)}
            </p>
          </div>
          <button
            type="button"
            phx-click="revoke"
            phx-value-id={code.id}
            phx-target={@myself}
            data-confirm={gettext("Revoke this code?")}
            class="btn btn-ghost btn-xs btn-square text-error"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </li>
      </ul>
    </div>
    """
  end
end
