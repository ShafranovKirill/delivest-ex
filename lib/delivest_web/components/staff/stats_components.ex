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
      "stat min-w-0 rounded-box border border-base-300 bg-base-100 p-3 sm:p-4 flex flex-col sm:flex-row items-start gap-2 sm:gap-3",
      @class
    ]}>
      <div :if={@icon} class="bg-primary/10 text-primary rounded-field p-2 shrink-0">
        <.icon name={@icon} class="size-5" />
      </div>
      <div class="min-w-0 flex-1">
        <p class="stat-title whitespace-normal uppercase tracking-wide font-semibold line-clamp-2 break-words">
          {@label}
        </p>
        <p class="stat-value whitespace-normal break-words text-lg sm:text-xl font-bold tabular-nums">
          {render_slot(@inner_block)}
        </p>
        <div
          :if={@hint || is_number(@delta)}
          class="stat-desc flex flex-wrap items-center gap-x-2 mt-0.5 min-h-5 whitespace-normal"
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
