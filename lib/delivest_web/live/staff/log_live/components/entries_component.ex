defmodule DelivestWeb.Staff.LogLive.Components.EntriesComponent do
  use DelivestWeb, :html

  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  attr :entries, :any, required: true

  def render_entries(assigns) do
    ~H"""
    <.table id="app-logs" rows={@entries}>
      <:col :let={{_id, entry}} label={gettext("Time")}>
        <span class="font-mono text-xs whitespace-nowrap">
          {OrderHelpers.local_datetime(entry.inserted_at)}
        </span>
      </:col>
      <:col :let={{_id, entry}} label={gettext("Level")}>
        <span class={["badge badge-sm uppercase", level_class(entry.level)]}>{entry.level}</span>
      </:col>
      <:col :let={{_id, entry}} label={gettext("Message")}>
        <details class="max-w-3xl">
          <summary class="cursor-pointer text-sm break-all line-clamp-2">
            {first_line(entry.message)}
          </summary>
          <div class="mt-2 space-y-1 text-xs">
            <p :if={entry.source} class="font-mono text-base-content/60">{entry.source}</p>
            <pre class="whitespace-pre-wrap break-all bg-base-200 rounded p-2">{entry.message}</pre>
            <p :for={{key, value} <- entry.metadata} class="font-mono text-base-content/60">
              {key}: {value}
            </p>
          </div>
        </details>
      </:col>
    </.table>
    """
  end

  defp first_line(message), do: message |> String.split("\n", parts: 2) |> hd()

  defp level_class(level) when level in ["error", "critical", "alert", "emergency"],
    do: "badge-error"

  defp level_class("warning"), do: "badge-warning"
  defp level_class("info"), do: "badge-info badge-soft"
  defp level_class(_level), do: "badge-ghost"
end
