defmodule DelivestWeb.Staff.OrderLive.Components.StatusTabs do
  use DelivestWeb, :html

  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  @statuses [:created, :accepted, :preparing, :ready, :delivering, :completed, :cancelled]

  attr :counts, :map, required: true
  attr :selected, :string, required: true
  attr :path_fn, :any, required: true

  def status_tabs(assigns) do
    assigns =
      assign(assigns, statuses: @statuses, total: assigns.counts |> Map.values() |> Enum.sum())

    ~H"""
    <nav id="order-status-tabs" class="flex gap-1.5 overflow-x-auto pb-1 -mb-1">
      <.tab
        label={gettext("All")}
        count={@total}
        active={@selected == ""}
        to={@path_fn.(%{"status" => nil})}
      />
      <.tab
        :for={status <- @statuses}
        id={"order-status-tab-#{status}"}
        label={OrderHelpers.status_label(status)}
        count={Map.get(@counts, status, 0)}
        active={@selected == Atom.to_string(status)}
        alert={status == :created and Map.get(@counts, status, 0) > 0}
        to={@path_fn.(%{"status" => Atom.to_string(status)})}
      />
    </nav>
    """
  end

  attr :id, :string, default: nil
  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :active, :boolean, required: true
  attr :alert, :boolean, default: false
  attr :to, :string, required: true

  defp tab(assigns) do
    ~H"""
    <.link
      id={@id}
      patch={@to}
      class={[
        "btn btn-sm shrink-0 gap-2 rounded-full",
        @active && "btn-primary",
        !@active && "btn-ghost bg-base-200/70"
      ]}
    >
      {@label}
      <span class={[
        "badge badge-sm font-mono",
        @alert && "badge-error animate-pulse",
        !@alert && @active && "bg-primary-content/20 border-0 text-primary-content",
        !@alert && !@active && "badge-ghost"
      ]}>
        {@count}
      </span>
    </.link>
    """
  end
end
