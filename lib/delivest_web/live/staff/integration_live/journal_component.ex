defmodule DelivestWeb.Staff.IntegrationLive.JournalComponent do
  use DelivestWeb, :live_component

  alias Delivest.Integrations.Journal
  alias Delivest.Integrations.Journal.Request
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  @impl true
  def mount(socket), do: {:ok, assign(socket, failed: false)}

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> load()}
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, load(socket)}

  def handle_event("failed", _params, socket),
    do: {:noreply, socket |> assign(failed: not socket.assigns.failed) |> load()}

  defp load(socket) do
    %{provider: provider, branch_id: branch_id, failed: failed} = socket.assigns
    assign(socket, requests: Journal.list(provider, branch_id, failed: failed))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="card bg-base-100 border border-base-300">
      <div class="card-body gap-4">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div>
            <h2 class="card-title text-base">{gettext("Request journal")}</h2>
            <p class="text-sm text-base-content/60">
              {gettext("The last requests to and from the service. Secrets are hidden.")}
            </p>
          </div>
          <div class="flex items-center gap-2">
            <label class="label cursor-pointer gap-2 text-sm">
              <input
                type="checkbox"
                class="toggle toggle-sm"
                checked={@failed}
                phx-click="failed"
                phx-target={@myself}
              />
              {gettext("Errors only")}
            </label>
            <button
              type="button"
              class="btn btn-sm btn-ghost"
              phx-click="refresh"
              phx-target={@myself}
              title={gettext("Refresh")}
            >
              <.icon name="hero-arrow-path" class="size-4" />
            </button>
          </div>
        </div>

        <p :if={@requests == []} class="text-sm text-base-content/60">
          {gettext("No requests yet.")}
        </p>

        <div :if={@requests != []} class="divide-y divide-base-300">
          <details :for={request <- @requests} id={"journal-#{request.id}"} class="group py-2">
            <summary class="flex cursor-pointer list-none items-center gap-3 text-sm">
              <span class={[
                "badge badge-sm tabular-nums",
                if(Request.failed?(request), do: "badge-error", else: "badge-ghost")
              ]}>
                {request.status || gettext("no response")}
              </span>
              <span class="text-base-content/60">
                <.icon
                  name={
                    if request.direction == :in,
                      do: "hero-arrow-down-left",
                      else: "hero-arrow-up-right"
                  }
                  class="size-4"
                />
              </span>
              <span class="font-mono text-xs">{request.method}</span>
              <span class="min-w-0 flex-1 truncate font-mono text-xs">{request.url}</span>
              <span :if={request.duration_ms} class="text-xs text-base-content/50 tabular-nums">
                {request.duration_ms} {gettext("ms")}
              </span>
              <span class="text-xs text-base-content/50 whitespace-nowrap">
                {OrderHelpers.local_datetime(request.inserted_at)}
              </span>
            </summary>
            <div class="mt-2 space-y-2 text-xs">
              <p :if={request.error} class="text-error">{request.error}</p>
              <.body :if={request.request} title={gettext("Request")} body={request.request} />
              <.body :if={request.response} title={gettext("Response")} body={request.response} />
            </div>
          </details>
        </div>
      </div>
    </section>
    """
  end

  attr :title, :string, required: true
  attr :body, :string, required: true

  defp body(assigns) do
    ~H"""
    <div>
      <div class="mb-1 font-semibold text-base-content/70">{@title}</div>
      <pre class="max-h-64 overflow-auto whitespace-pre-wrap break-all rounded bg-base-200 p-2">{@body}</pre>
    </div>
    """
  end
end
