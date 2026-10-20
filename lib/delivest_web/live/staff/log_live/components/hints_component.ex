defmodule DelivestWeb.Staff.LogLive.Components.HintsComponent do
  use DelivestWeb, :html

  alias DelivestWeb.Staff.LogLive.HintText
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  attr :entries, :any, required: true

  def render_hints(assigns) do
    ~H"""
    <div id="app-hints" phx-update="stream" class="space-y-2">
      <p
        id="hints-empty"
        class="hidden only:block rounded-box border border-dashed border-base-300 p-8 text-center text-sm text-base-content/60"
      >
        {gettext("No hints: the catalog matches the CRM.")}
      </p>
      <div
        :for={{id, entry} <- @entries}
        id={id}
        class="flex items-start gap-3 rounded-box border border-warning/30 bg-warning/5 p-3"
      >
        <div class="size-9 shrink-0 rounded-full bg-warning/15 text-warning flex items-center justify-center">
          <.icon name={HintText.icon(entry.metadata)} class="size-5" />
        </div>
        <div class="min-w-0 flex-1">
          <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
            <span class="font-bold text-sm">{HintText.title(entry.metadata)}</span>
            <span class="badge badge-ghost badge-sm">{entry.metadata["hint_branch"]}</span>
            <span class="text-xs text-base-content/50 font-mono ml-auto">
              {OrderHelpers.local_datetime(entry.inserted_at)}
            </span>
          </div>
          <p class="text-sm mt-1 break-words">
            {HintText.describe(entry.metadata) || entry.message}
          </p>
        </div>
      </div>
    </div>
    """
  end
end
