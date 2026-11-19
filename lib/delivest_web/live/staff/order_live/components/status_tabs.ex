defmodule DelivestWeb.Staff.OrderLive.Components.StatusTabs do
  use DelivestWeb, :html

  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  @statuses [:created, :accepted, :preparing, :ready, :delivering, :completed, :cancelled]

  attr :counts, :map, required: true
  attr :selected, :string, required: true
  attr :path_fn, :any, required: true

  def status_tabs(assigns) do
    assigns =
      assign(assigns,
        statuses: @statuses,
        total: assigns.counts |> Map.values() |> Enum.sum(),
        selected_label:
          case Enum.find(@statuses, &(Atom.to_string(&1) == assigns.selected)) do
            nil -> gettext("All statuses")
            status -> OrderHelpers.status_label(status)
          end
      )

    ~H"""
    <nav id="order-status-tabs" aria-label={gettext("Status")}>
      <details class="dropdown w-full">
        <summary id="order-status-select" class="btn btn-sm btn-outline w-full justify-between">
          <span class="truncate">{@selected_label}</span>
          <.icon name="hero-chevron-down" class="size-4 shrink-0" />
        </summary>
        <div class="dropdown-content z-20 mt-1 max-h-80 w-full overflow-y-auto rounded-box border border-base-300 bg-base-100 p-1 shadow-lg">
          <.tab
            id="order-status-tab-all"
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
            to={@path_fn.(%{"status" => Atom.to_string(status)})}
          />
        </div>
      </details>
    </nav>
    """
  end

  attr :id, :string, default: nil
  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :active, :boolean, required: true
  attr :to, :string, required: true

  defp tab(assigns) do
    ~H"""
    <.link
      id={@id}
      patch={@to}
      aria-current={@active && "page"}
      class={[
        "flex w-full items-center justify-between rounded-field px-3 py-2 text-left text-sm hover:bg-base-200",
        @active && "btn-primary",
        !@active && "bg-base-100"
      ]}
    >
      {@label}
      <span class={[
        "badge badge-sm font-mono",
        @active && "bg-primary-content/20 border-0 text-primary-content",
        !@active && "badge-ghost"
      ]}>
        {@count}
      </span>
    </.link>
    """
  end
end
