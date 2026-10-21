defmodule DelivestWeb.Staff.LogLive.Components.EventsComponent do
  use DelivestWeb, :html

  alias DelivestWeb.Staff.LogLive.EventText
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  attr :events, :any, required: true
  attr :branches, :map, default: %{}
  attr :actor_path, :any, required: true

  def render_events(assigns) do
    ~H"""
    <.table id="audit-events" rows={@events}>
      <:col :let={{_id, event}} label={gettext("Time")}>
        <span class="font-mono text-xs whitespace-nowrap">
          {OrderHelpers.local_datetime(event.inserted_at)}
        </span>
      </:col>
      <:col :let={{_id, event}} label={gettext("Who")}>
        <.link
          :if={event.actor_type == :staff and event.actor_id}
          patch={@actor_path.(event.actor_id)}
          class={["badge badge-sm whitespace-nowrap hover:underline", actor_class(event.actor_type)]}
          title={gettext("Show events of this employee")}
        >
          {EventText.actor(event)}
        </.link>
        <span
          :if={!(event.actor_type == :staff and event.actor_id)}
          class={["badge badge-sm whitespace-nowrap", actor_class(event.actor_type)]}
        >
          {EventText.actor(event)}
        </span>
      </:col>
      <:col :let={{_id, event}} label={gettext("What happened")}>
        <span class="text-sm">{EventText.describe(event)}</span>
      </:col>
      <:col :let={{_id, event}} label={gettext("Branch")} secondary>
        <span class="text-xs text-base-content/70 whitespace-nowrap">
          {event.branch_name || Map.get(@branches, event.branch_id, "—")}
        </span>
      </:col>
    </.table>
    """
  end

  defp actor_class(:staff), do: "badge-primary badge-soft"
  defp actor_class(:client), do: "badge-success badge-soft"
  defp actor_class(:guest), do: "badge-ghost"
  defp actor_class(:system), do: "badge-neutral badge-soft"
end
