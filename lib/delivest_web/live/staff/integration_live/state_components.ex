defmodule DelivestWeb.Staff.IntegrationLive.StateComponents do
  @moduledoc """
  Shared rendering of the three independent integration facts.
  """

  use DelivestWeb, :html

  alias Delivest.LocalTime
  alias DelivestWeb.Staff.IntegrationLive.Presentation

  attr :state, :map, required: true
  attr :id, :string, required: true
  attr :branch, :any, default: nil
  slot :action

  def summary(assigns) do
    ~H"""
    <div id={@id} class="space-y-2 rounded-box border border-base-300 bg-base-100 p-4 text-sm">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <.scope_badge scope={@state.scope} />
        {render_slot(@action)}
      </div>
      <.credentials_row id={"#{@id}-credentials"} credentials={@state.credentials} />
      <.connection_row
        id={"#{@id}-connection"}
        connection={@state.connection}
        branch={@branch}
      />
      <.usage_rows id={"#{@id}-usage"} usage={@state.usage} />
      <.warning_rows id={"#{@id}-warnings"} warnings={@state.warnings} />
    </div>
    """
  end

  attr :scope, :any, required: true

  def scope_badge(assigns) do
    ~H"""
    <p class="text-xs font-medium text-base-content/60">{Presentation.scope_text(@scope)}</p>
    """
  end

  attr :id, :string, required: true
  attr :credentials, :map, required: true

  def credentials_row(assigns) do
    ~H"""
    <div id={@id} class="flex flex-wrap items-center justify-between gap-2">
      <span class="text-base-content/70">{gettext("Connection data")}</span>
      <span class={["badge badge-sm", credential_class(@credentials.state)]}>
        {@credentials.text}
      </span>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :connection, :map, required: true
  attr :branch, :any, default: nil

  def connection_row(assigns) do
    ~H"""
    <div id={@id} class="flex flex-wrap items-center justify-between gap-2">
      <span class="text-base-content/70">{gettext("Connection check")}</span>
      <span class="flex flex-wrap items-center gap-2">
        <span class={["badge badge-sm", connection_class(@connection.state)]}>
          {@connection.text}
        </span>
        <span :if={@connection.checked_at} class="text-xs text-base-content/60">
          {format_time(@connection.checked_at, @branch)}
        </span>
      </span>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :usage, :list, required: true

  def usage_rows(assigns) do
    ~H"""
    <div id={@id} class="space-y-1">
      <div
        :for={item <- @usage}
        id={"#{@id}-#{usage_key(item.label)}"}
        class="flex flex-wrap items-center justify-between gap-2"
      >
        <span class="text-base-content/70">{item.label}</span>
        <span class={["badge badge-sm", usage_class(item.state)]}>{usage_text(item.state)}</span>
        <p :if={item.detail} class="w-full text-xs text-base-content/60">{item.detail}</p>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :warnings, :list, required: true

  def warning_rows(assigns) do
    ~H"""
    <div :if={@warnings != []} id={@id} class="space-y-1">
      <p class="flex items-start gap-1 text-xs text-warning">
        <.icon name="hero-exclamation-triangle" class="mt-0.5 size-3.5 shrink-0" />
        <span>
          <span class="font-medium">{gettext("Needs attention")}:</span>
          <span :for={warning <- @warnings}>{warning.text}</span>
        </span>
      </p>
    </div>
    """
  end

  def usage_text(:on), do: gettext("On")
  def usage_text(:off), do: gettext("Off")
  def usage_text(:not_ready), do: gettext("Not ready")
  def usage_text(:paused), do: gettext("Paused")

  defp usage_class(:on), do: "badge-success"
  defp usage_class(:not_ready), do: "badge-warning"
  defp usage_class(:paused), do: "badge-warning"
  defp usage_class(_state), do: "badge-ghost text-base-content/60"

  defp credential_class(:complete), do: "badge-success"
  defp credential_class(:partial), do: "badge-warning"
  defp credential_class(:not_required), do: "badge-ghost text-base-content/60"
  defp credential_class(_state), do: "badge-ghost text-base-content/60"

  defp connection_class(:ok), do: "badge-success"
  defp connection_class(:auth), do: "badge-error"
  defp connection_class(:failed), do: "badge-warning"
  defp connection_class(_state), do: "badge-ghost text-base-content/60"

  defp usage_key(label) do
    label
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-zа-я0-9]+/u, "-")
  end

  defp format_time(%DateTime{} = at, branch) do
    at
    |> LocalTime.local(branch && branch.id)
    |> Calendar.strftime("%d.%m.%Y %H:%M")
  end
end
