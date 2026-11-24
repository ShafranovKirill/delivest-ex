defmodule DelivestWeb.Staff.FinanceLive.Transactions do
  use DelivestWeb, :live_view

  import DelivestWeb.Staff.FoundationComponents,
    only: [filter_bar: 1, pagination_footer: 1, status_badge: 1]

  alias Delivest.{Identity, Payments}

  on_mount {DelivestWeb.Hooks.Permission, "finance.read"}

  @statuses ~w(pending authorized paid failed cancelled)

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, page_title: gettext("Payments"))}

  @impl true
  def handle_params(params, _url, socket) do
    query =
      params
      |> Map.take(~w(status search from to page page_size))
      |> Map.filter(fn {_key, value} -> is_binary(value) end)

    {rows, pagination} = Payments.list_branch_page(socket.assigns.current_branch.id, query)
    {:noreply, assign(socket, query: query, rows: rows, pagination: pagination)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    query =
      socket.assigns.query
      |> Map.merge(Map.take(params, ~w(status search from to)))
      |> Map.put("page", 1)

    {:noreply, push_patch(socket, to: transactions_path(socket.assigns, query))}
  end

  def handle_event("update_page_size", %{"page_size" => size}, socket) do
    query = Map.merge(socket.assigns.query, %{"page_size" => size, "page" => 1})
    {:noreply, push_patch(socket, to: transactions_path(socket.assigns, query))}
  end

  def staff_page_header(assigns) do
    assigns = assign(assigns, statuses: @statuses)

    ~H"""
    <.page_toolbar id="transactions-toolbar" title={gettext("Payments")}>
      <:filters>
        <.filter_bar
          id="transactions-filter"
          query={@query["search"] || ""}
          query_name="search"
          reset_path={transactions_path(assigns, %{})}
          event="filter"
          active={
            @query["status"] not in [nil, ""] or @query["from"] not in [nil, ""] or
              @query["to"] not in [nil, ""]
          }
          compact
        >
          <:filter>
            <div>
              <label for="transactions-status" class="sr-only">{gettext("Status")}</label>
              <select
                id="transactions-status"
                name="status"
                class="select select-bordered select-sm w-32"
              >
                <option value="">{gettext("All statuses")}</option>
                <option :for={value <- @statuses} value={value} selected={@query["status"] == value}>
                  {status(String.to_existing_atom(value))}
                </option>
              </select>
            </div>
            <div>
              <label for="transactions-from" class="sr-only">{gettext("From")}</label>
              <input
                id="transactions-from"
                name="from"
                type="date"
                value={@query["from"]}
                class="input input-bordered input-sm w-32"
              />
            </div>
            <div>
              <label for="transactions-to" class="sr-only">{gettext("To")}</label>
              <input
                id="transactions-to"
                name="to"
                type="date"
                value={@query["to"]}
                class="input input-bordered input-sm w-32"
              />
            </div>
          </:filter>
        </.filter_bar>
      </:filters>
      <:more_actions>
        <.link
          navigate={~p"/staff/b/#{@current_branch}/finance/payments"}
          class="btn btn-ghost btn-sm justify-start"
        >{gettext("Payment methods")}</.link>
      </:more_actions>
    </.page_toolbar>
    """
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, statuses: @statuses)

    ~H"""
    <div id="transactions-page" class="space-y-5">
      <.table
        id="transactions"
        rows={@rows}
        row_id={fn {payment, _number} -> "payment-row-#{payment.id}" end}
        empty_title={if @query == %{}, do: gettext("No payments yet"), else: gettext("Nothing found")}
      >
        <:col :let={{payment, number}} key="order" label={gettext("Order")}>
          <.link
            :if={Identity.authorize(@current_staff, "orders.read", @current_branch.id) == :ok}
            navigate={~p"/staff/b/#{@current_branch}/orders/#{payment.order_id}"}
            class="link link-primary"
          >{number}</.link>
          <span :if={Identity.authorize(@current_staff, "orders.read", @current_branch.id) != :ok}>{number}</span>
        </:col>
        <:col :let={{payment, _number}} key="amount" label={gettext("Amount")} numeric>
          <span class="tabular-nums">{Delivest.Money.format(payment.amount)}</span>
        </:col>
        <:col :let={{payment, _number}} key="status" label={gettext("Status")}>
          <.status_badge
            id={"payment-status-#{payment.id}"}
            label={status(payment.status)}
            tone={status_tone(payment.status)}
            class="badge-sm whitespace-nowrap"
          />
        </:col>
        <:col :let={{payment, _number}} key="method" label={gettext("Method")} secondary>
          {method(payment.method)}
        </:col>
        <:col :let={{payment, _number}} key="provider" label={gettext("Provider")} secondary>
          {payment.provider || "—"}
        </:col>
        <:col :let={{payment, _number}} key="external_id" label={gettext("External ID")} secondary>
          {payment.external_id || "—"}
        </:col>
        <:col :let={{payment, _number}} key="created" label={gettext("Created at")}>
          {payment.inserted_at
          |> Delivest.LocalTime.local(@current_branch)
          |> Calendar.strftime("%d.%m %H:%M")}
        </:col>
      </.table>

      <.pagination_footer
        id="transactions-footer"
        page_size_id="transactions-page-size"
        count_label={gettext("%{count} payments", count: @pagination.total)}
        page={@pagination}
        path_fn={fn overrides -> transactions_path(assigns, Map.merge(@query, overrides)) end}
      />
    </div>
    """
  end

  defp transactions_path(assigns, params) do
    params = Map.reject(params, fn {_key, value} -> value in [nil, "", []] end)
    ~p"/staff/b/#{assigns.current_branch}/finance/transactions?#{params}"
  end

  defp status(:pending), do: gettext("Pending")
  defp status(:authorized), do: gettext("Authorized")
  defp status(:paid), do: gettext("Paid")
  defp status(:failed), do: gettext("Failed")
  defp status(:cancelled), do: gettext("Cancelled")

  defp status_tone(:paid), do: :success
  defp status_tone(status) when status in [:failed, :cancelled], do: :error
  defp status_tone(_), do: :warning

  defp method(:cash), do: gettext("Cash")
  defp method(:card), do: gettext("Card")
  defp method(:online), do: gettext("Online")
  defp method(:sbp), do: gettext("SBP")
  defp method(:certificate), do: gettext("Certificate")
  defp method(:aggregator), do: gettext("Aggregator")
  defp method(_), do: "—"
end
