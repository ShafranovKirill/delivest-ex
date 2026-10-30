defmodule DelivestWeb.Staff.OrderLive.Components.OrdersToolbar do
  use DelivestWeb, :html

  attr :selected, :map, required: true

  def orders_toolbar(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row flex-wrap gap-3 justify-between items-stretch sm:items-center">
      <.form
        for={%{}}
        id="orders-filter"
        phx-change="filter"
        class="flex flex-wrap items-center gap-2"
      >
        <label class="input input-sm w-full sm:w-72">
          <.icon name="hero-magnifying-glass" class="size-4 text-base-content/50" />
          <input
            id="orders-search"
            type="search"
            name="search"
            value={@selected.search}
            placeholder={gettext("Number, phone, name or address")}
            phx-debounce="300"
            autocomplete="off"
            class="grow"
          />
        </label>
        <select name="period" class="select select-bordered select-sm w-full sm:w-44">
          <option
            :for={{value, label} <- periods()}
            value={value}
            selected={@selected.period == value}
          >
            {label}
          </option>
        </select>
        <label class="label cursor-pointer gap-2 py-0">
          <input type="hidden" name="problem" value="false" />
          <input
            id="orders-problem"
            type="checkbox"
            name="problem"
            value="true"
            checked={@selected.problem}
            class="checkbox checkbox-sm"
          />
          <span class="text-sm">{gettext("With a problem")}</span>
        </label>
        <div :if={@selected.period == "custom"} class="flex items-center gap-1">
          <input
            type="date"
            name="date_from"
            value={@selected.date_from}
            class="input input-bordered input-sm"
          />
          <span class="text-base-content/40">—</span>
          <input
            type="date"
            name="date_to"
            value={@selected.date_to}
            class="input input-bordered input-sm"
          />
        </div>
      </.form>

      <div class="flex items-center gap-2">
        <div class="join" role="radiogroup" aria-label={gettext("Sort")}>
          <button
            :for={{value, label, icon} <- sorts()}
            id={"orders-sort-#{value}"}
            type="button"
            role="radio"
            aria-checked={to_string(@selected.sort == value)}
            phx-click="sort"
            phx-value-sort={value}
            class={["join-item btn btn-sm", @selected.sort == value && "btn-active"]}
          >
            <.icon name={icon} class="size-4" /> {label}
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp periods do
    [
      {"today", gettext("Today")},
      {"tomorrow", gettext("Tomorrow")},
      {"yesterday", gettext("Yesterday")},
      {"week", gettext("Week")},
      {"month", gettext("Month")},
      {"all", gettext("All")},
      {"custom", gettext("Custom")}
    ]
  end

  defp sorts do
    [
      {"urgency", gettext("By urgency"), "hero-fire"},
      {"time", gettext("By time"), "hero-clock"}
    ]
  end
end
