defmodule DelivestWeb.Staff.StatsComponents do
  use Phoenix.Component
  use Gettext, backend: DelivestWeb.Gettext

  import DelivestWeb.CoreComponents, only: [icon: 1]

  attr :icon, :string, default: nil
  attr :label, :string, required: true
  attr :delta, :any, default: nil
  attr :hint, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def stat_card(assigns) do
    ~H"""
    <div class={[
      "statistics-metric-card min-w-0 rounded-xl border border-base-300 p-4 sm:p-5",
      @class
    ]}>
      <div class="flex min-w-0 items-start justify-between gap-3">
        <p class="statistics-metric-label min-w-0 whitespace-normal break-words text-sm font-medium">
          {@label}
        </p>
        <.icon :if={@icon} name={@icon} class="statistics-metric-icon size-4 shrink-0" />
      </div>
      <div class="mt-4 min-w-0">
        <p class="statistics-metric-value whitespace-normal break-words text-2xl font-semibold tracking-tight tabular-nums">
          {render_slot(@inner_block)}
        </p>
        <div
          :if={@hint || is_number(@delta)}
          class="statistics-metric-detail mt-1 flex min-h-5 flex-wrap items-center gap-x-2 whitespace-normal"
        >
          <span
            :if={is_number(@delta)}
            class={[
              "badge badge-xs font-semibold tabular-nums",
              cond do
                @delta > 0 -> "badge-success"
                @delta < 0 -> "badge-error"
                true -> "badge-ghost"
              end
            ]}
          >
            {if @delta > 0, do: "+"}{@delta}%
          </span>
          <span :if={@hint} class="text-xs text-base-content/50">{@hint}</span>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :data, :map, required: true
  attr :label, :string, required: true
  attr :height, :string, default: "h-64"
  slot :inner_block

  def analytics_chart(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="AnalyticsChart"
      data-chart={Jason.encode!(@data)}
      class="min-w-0"
    >
      <div phx-update="ignore" id={"#{@id}-canvas"}>
        <div
          id={"#{@id}-plot"}
          class={["w-full", @height]}
          role="img"
          aria-label={@label}
        >
        </div>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  def delta(_current, previous) when previous in [0, nil], do: nil
  def delta(current, previous), do: Float.round((current - previous) * 100 / previous, 1)
end
