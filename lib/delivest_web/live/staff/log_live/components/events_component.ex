defmodule DelivestWeb.Staff.LogLive.Components.EventsComponent do
  use DelivestWeb, :html

  alias DelivestWeb.Staff.LogLive.EventText
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  attr :events, :any, required: true

  def render_events(assigns) do
    ~H"""
    <.table id="audit-events" rows={@events}>
      <:col :let={{_id, event}} label={gettext("Time")}>
        <span class="font-mono text-xs whitespace-nowrap">
          {OrderHelpers.local_datetime(event.inserted_at)}
        </span>
      </:col>
      <:col :let={{_id, event}} label={gettext("Who")}>
        <span class={["badge badge-sm whitespace-nowrap", actor_class(event.actor_type)]}>
          {EventText.actor(event)}
        </span>
      </:col>
      <:col :let={{_id, event}} label={gettext("What happened")}>
        <span class="text-sm">{EventText.describe(event)}</span>
      </:col>
    </.table>
    """
  end

  defp actor_class(:staff), do: "badge-primary badge-soft"
  defp actor_class(:client), do: "badge-success badge-soft"
  defp actor_class(:guest), do: "badge-ghost"
  defp actor_class(:system), do: "badge-neutral badge-soft"
end
