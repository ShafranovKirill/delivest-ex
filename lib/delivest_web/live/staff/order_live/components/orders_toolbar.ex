defmodule DelivestWeb.Staff.OrderLive.Components.OrdersToolbar do
  use DelivestWeb, :html
  import DelivestWeb.Staff.FoundationComponents, only: [filter_bar: 1]

  attr :selected, :map, required: true
  attr :reset_path, :string, required: true

  def orders_toolbar(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row flex-wrap gap-3 justify-between items-stretch sm:items-center">
      <.filter_bar
        id="orders-filter"
        query={@selected.search}
        query_name="search"
        query_input_id="orders-search"
        query_placeholder={gettext("Number, phone, name or address")}
        reset_path={@reset_path}
        event="filter"
        active={
          @selected.period != "today" or @selected.problem or @selected.receiving != "" or
            @selected.payment != "" or @selected.source != ""
        }
      >
        <:filter>
          <label for="orders-period" class="sr-only">{gettext("Period")}</label>
          <select
            id="orders-period"
            name="period"
            class="select select-bordered select-sm w-full sm:w-44"
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
          <select id="orders-receiving" name="receiving" class="select select-bordered select-sm">
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
          <select id="orders-payment" name="payment" class="select select-bordered select-sm">
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
          <select id="orders-source" name="source" class="select select-bordered select-sm">
            <option value="">{gettext("All sources")}</option>
            <option
              :for={source <- Delivest.Oms.OrderSource.all()}
              value={source}
              selected={@selected.source == source}
            >
              {source_label(source)}
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
        </:filter>
      </.filter_bar>

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

  defp source_label("app"), do: gettext("App")
  defp source_label("staff"), do: gettext("Admin")
  defp source_label("pos"), do: gettext("POS")
  defp source_label(source), do: Delivest.Integrations.Channels.name(source)
end
