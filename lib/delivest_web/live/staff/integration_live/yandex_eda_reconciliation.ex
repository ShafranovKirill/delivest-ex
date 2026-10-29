defmodule DelivestWeb.Staff.IntegrationLive.YandexEdaReconciliation do
  use DelivestWeb, :html

  alias Delivest.Money
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  attr :date, Date, required: true
  attr :result, :any, default: nil

  def reconciliation(assigns) do
    ~H"""
    <section
      id="yandex-eda-reconciliation"
      class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
    >
      <div>
        <h2 class="font-bold">{gettext("Orders reconciliation")}</h2>
        <p class="text-sm text-base-content/60">
          {gettext(
            "Compares the Yandex Eda order history of the day with our orders and shows only the differences."
          )}
        </p>
      </div>

      <form id="yandex-eda-reconcile" phx-submit="reconcile" class="flex items-end gap-3">
        <.input name="date" type="date" label={gettext("Day")} value={Date.to_iso8601(@date)} />
        <button type="submit" class="btn" phx-disable-with={gettext("Loading...")}>
          <.icon name="hero-arrows-right-left" class="size-4" />
          {gettext("Reconcile")}
        </button>
      </form>

      <.async_result :let={result} :if={@result} assign={@result}>
        <:loading>
          <p class="text-sm text-base-content/50">{gettext("Loading...")}</p>
        </:loading>
        <:failed>
          <p class="text-sm text-error">{gettext("Yandex did not return the order history")}</p>
        </:failed>

        <p id="yandex-eda-reconciliation-summary" class="text-sm">
          {gettext("Orders in Yandex: %{total}, differences: %{problems}",
            total: result.total,
            problems: length(result.problems)
          )}
        </p>

        <ul :if={result.problems != []} class="divide-y divide-base-300 text-sm">
          <li
            :for={row <- result.problems}
            id={"yandex-eda-reconciliation-#{row.eats_id}"}
            class="flex flex-wrap items-center gap-x-3 gap-y-1 py-2"
          >
            <span class="font-mono">{row.eats_id}</span>
            <span :if={row.order} class="font-mono text-primary">#{row.order.number}</span>
            <span class="badge badge-sm badge-warning">{problem_label(row.problem)}</span>
            <span :if={row.remote} class="text-base-content/60">
              {remote_status(row.remote["status"])} · {OrderHelpers.money(items_cost(row.remote))}
            </span>
            <span :if={row.order} class="text-base-content/60">
              {gettext("ours")}: {OrderHelpers.status_label(row.order.status)}
            </span>
          </li>
        </ul>
      </.async_result>
    </section>
    """
  end

  defp items_cost(%{"items_cost" => cost}) when is_number(cost), do: Money.from_rubles(cost)
  defp items_cost(_remote), do: nil

  defp problem_label(:missing), do: gettext("No such order here")
  defp problem_label(:not_in_yandex), do: gettext("Not in Yandex history")
  defp problem_label(:cancelled_in_yandex), do: gettext("Cancelled in Yandex, not here")
  defp problem_label(:cancelled_here), do: gettext("Delivered in Yandex, cancelled here")

  defp remote_status("NEW"), do: gettext("In progress in Yandex")
  defp remote_status("DELIVERED"), do: gettext("Delivered in Yandex")
  defp remote_status("CANCELLED"), do: gettext("Cancelled in Yandex")
  defp remote_status(_status), do: gettext("Status unknown")
end
