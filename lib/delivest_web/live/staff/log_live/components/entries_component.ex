defmodule DelivestWeb.Staff.LogLive.Components.EntriesComponent do
  use DelivestWeb, :html

  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  attr :entries, :any, required: true
  attr :staff_id, :string, required: true

  def render_entries(assigns) do
    ~H"""
    <.table id="app-logs" rows={@entries} staff_id={@staff_id} list_id="staff-raw-logs">
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
            {first_line(redact(entry.message))}
          </summary>
          <div class="mt-2 space-y-1 text-xs">
            <p :if={entry.source} class="font-mono text-base-content/60">{redact(entry.source)}</p>
            <pre class="whitespace-pre-wrap break-all bg-base-200 rounded p-2">{redact(entry.message)}</pre>
            <p :for={{key, value} <- entry.metadata} class="font-mono text-base-content/60">
              {key}: {redact_metadata(key, value)}
            </p>
          </div>
        </details>
      </:col>
    </.table>
    """
  end

  defp first_line(message), do: message |> String.split("\n", parts: 2) |> hd()

  @sensitive_key ~r/password|secret|token|api[_-]?key|authorization|cookie|credential/i
  @sensitive_value ~r/((?:password|secret|token|api[_-]?key|authorization|cookie|credential)\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;&]+)/i
  @bearer ~r/(Bearer\s+)[A-Za-z0-9._~+\/=\-]+/i

  defp redact(value) when is_binary(value) do
    value = Regex.replace(@bearer, value, "\\1[REDACTED]")
    Regex.replace(@sensitive_value, value, "\\1[REDACTED]")
  end

  defp redact(value), do: to_string(value)

  defp redact_metadata(key, value) do
    if Regex.match?(@sensitive_key, to_string(key)),
      do: "[REDACTED]",
      else: redact_nested(value)
  end

  defp redact_nested(value) when is_map(value) do
    value
    |> Map.new(fn {key, item} -> {key, redact_metadata(key, item)} end)
    |> inspect()
  end

  defp redact_nested(value) when is_list(value), do: inspect(Enum.map(value, &redact_nested/1))
  defp redact_nested(value) when is_binary(value), do: redact(value)
  defp redact_nested(value), do: inspect(value)

  defp level_class(level) when level in ["error", "critical", "alert", "emergency"],
    do: "badge-error"

  defp level_class("warning"), do: "badge-warning"
  defp level_class("info"), do: "badge-info badge-soft"
  defp level_class(_level), do: "badge-ghost"
end
