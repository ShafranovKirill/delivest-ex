defmodule DelivestWeb.Staff.OrderLive.Components.OrdersToolbar do
  use DelivestWeb, :html
  attr :selected, :map, required: true
  attr :reset_path, :string, required: true

  def orders_toolbar(assigns) do
    ~H"""
    <div id="orders-filter" class="contents">
      <form
        id="orders-filter-form"
        phx-change="filter"
        phx-submit="filter"
        role="search"
        class="contents"
      >
        <div class="orders-search-field min-w-0">
          <label for="orders-search" class="sr-only">{gettext("Search")}</label>
          <input
            id="orders-search"
            type="search"
            name="search"
            value={@selected.search}
            placeholder={gettext("Number, phone, name or address")}
            phx-debounce="350"
            class="input input-sm w-full"
          />
        </div>
        <div class="orders-filter-fields flex min-w-0 flex-wrap items-center gap-2">
          <label for="orders-period" class="sr-only">{gettext("Period")}</label>
          <select
            id="orders-period"
            name="period"
            class="select select-bordered select-sm min-w-28 flex-1"
          >
            <option
              :for={{value, label} <- periods()}
              value={value}
              selected={@selected.period == value}
            >
              {label}
            </option>
          </select>
          <label for="orders-receiving" class="sr-only">{gettext("Receiving")}</label>
          <select
            id="orders-receiving"
            name="receiving"
            class="select select-bordered select-sm min-w-32 flex-1"
          >
            <option value="">{gettext("All receiving types")}</option>
            <option value="dine_in" selected={@selected.receiving == "dine_in"}>
              {gettext("Dine in")}
            </option>
            <option value="delivery" selected={@selected.receiving == "delivery"}>
              {gettext("Delivery")}
            </option>
            <option value="pickup" selected={@selected.receiving == "pickup"}>
              {gettext("Pickup")}
            </option>
          </select>
          <label for="orders-payment" class="sr-only">{gettext("Payment")}</label>
          <select
            id="orders-payment"
            name="payment"
            class="select select-bordered select-sm min-w-28 flex-1"
          >
            <option value="">{gettext("All payment methods")}</option>
            <option value="cash" selected={@selected.payment == "cash"}>{gettext("Cash")}</option>
            <option value="card_offline" selected={@selected.payment == "card_offline"}>
              {gettext("Card")}
            </option>
            <option value="online" selected={@selected.payment == "online"}>
              {gettext("Online")}
            </option>
          </select>
          <label for="orders-source" class="sr-only">{gettext("Source")}</label>
          <select
            id="orders-source"
            name="source"
            class="select select-bordered select-sm min-w-28 flex-1"
          >
            <option value="">{gettext("All sources")}</option>
            <option
              :for={source <- Delivest.Oms.OrderSource.all()}
              value={source}
              selected={@selected.source == source}
            >
              {source_label(source)}
            </option>
          </select>
          <label class="label cursor-pointer gap-1.5 whitespace-nowrap py-0">
            <input type="hidden" name="problem" value="false" />
            <input
              id="orders-problem"
              type="checkbox"
              name="problem"
              value="true"
              checked={@selected.problem}
              class="checkbox checkbox-sm"
            />
            <span class="text-sm">{gettext("Needs attention")}</span>
          </label>
          <button type="submit" class="btn btn-sm btn-outline">{gettext("Apply")}</button>
          <.link
            :if={
              @selected.period != "today" or @selected.problem or @selected.receiving != "" or
                @selected.payment != "" or @selected.source != "" or @selected.search != ""
            }
            patch={@reset_path}
            class="btn btn-sm btn-ghost"
          >{gettext("Reset")}</.link>
        </div>
        <div
          :if={@selected.period == "custom"}
          class="orders-date-range flex min-w-0 items-center gap-1"
        >
          <label for="orders-date-from" class="sr-only">{gettext("From")}</label>
          <input
            id="orders-date-from"
            type="date"
            name="date_from"
            value={@selected.date_from}
            class="input input-bordered input-sm min-w-0 w-32"
          />
          <span class="text-base-content/40">—</span>
          <label for="orders-date-to" class="sr-only">{gettext("To")}</label>
          <input
            id="orders-date-to"
            type="date"
            name="date_to"
            value={@selected.date_to}
            class="input input-bordered input-sm min-w-0 w-32"
          />
        </div>
      </form>

      <div class="orders-sort flex items-center justify-end">
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

  defp source_label("app"), do: gettext("App")
  defp source_label("staff"), do: gettext("Admin")
  defp source_label("pos"), do: gettext("POS")
  defp source_label(source), do: Delivest.Integrations.Channels.name(source)
end
