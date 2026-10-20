defmodule DelivestWeb.Staff.StatsComponents do
  use Phoenix.Component
  use Gettext, backend: DelivestWeb.Gettext

  import DelivestWeb.CoreComponents, only: [icon: 1]

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :delta, :any, default: nil
  attr :hint, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def stat_card(assigns) do
    ~H"""
    <div class={[
      "bg-base-100 rounded-box border border-base-200 shadow-sm p-3 sm:p-4 flex flex-col sm:flex-row items-start gap-2 sm:gap-3",
      @class
    ]}>
      <div class="bg-primary/10 text-primary rounded-field p-2 shrink-0">
        <.icon name={@icon} class="size-5" />
      </div>
      <div class="min-w-0 flex-1">
        <p class="text-xs text-base-content/60 uppercase tracking-wide font-semibold line-clamp-2 break-words">
          {@label}
        </p>
        <p class="text-lg sm:text-xl font-bold tabular-nums whitespace-nowrap">
          {render_slot(@inner_block)}
        </p>
        <div class="flex flex-wrap items-center gap-x-2 mt-0.5 min-h-5">
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

  attr :rows, :list, required: true
  attr :value, :any, required: true, doc: "fn row -> number"
  attr :label, :any, required: true, doc: "fn row -> axis label"
  attr :title, :any, required: true, doc: "fn row -> tooltip text"
  attr :height, :string, default: "h-48"
  attr :label_every, :integer, default: 1, doc: "show every n-th axis label"

  def bar_chart(assigns) do
    max = assigns.rows |> Enum.map(assigns.value) |> Enum.max(fn -> 0 end)
    assigns = assign(assigns, :max, max(max, 1))

    ~H"""
    <div class="w-full">
      <div class={["flex items-end gap-0.5 sm:gap-1", @height]}>
        <div
          :for={row <- @rows}
          class="group relative flex-1 h-full flex items-end"
          title={@title.(row)}
        >
          <div
            class={[
              "w-full rounded-t-sm transition-colors",
              if(@value.(row) > 0,
                do: "bg-primary/70 group-hover:bg-primary",
                else: "bg-base-200"
              )
            ]}
            style={"height: #{max(@value.(row) / @max * 100, 2)}%"}
          />
        </div>
      </div>
      <div class="flex gap-0.5 sm:gap-1 mt-1 h-4">
        <div :for={{row, index} <- Enum.with_index(@rows)} class="relative flex-1">
          <span
            :if={rem(index, @label_every) == 0}
            class="absolute left-1/2 -translate-x-1/2 whitespace-nowrap text-[10px] text-base-content/50 tabular-nums"
          >
            {@label.(row)}
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr :value, :any, required: true

  def share_bar(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <div class="h-2 flex-1 rounded-full bg-base-200 overflow-hidden">
        <div class="h-full rounded-full bg-primary" style={"width: #{min(@value, 100)}%"} />
      </div>
      <span class="w-12 text-right text-xs tabular-nums text-base-content/60">{@value}%</span>
    </div>
    """
  end

  def delta(_current, previous) when previous in [0, nil], do: nil
  def delta(current, previous), do: Float.round((current - previous) * 100 / previous, 1)
end
