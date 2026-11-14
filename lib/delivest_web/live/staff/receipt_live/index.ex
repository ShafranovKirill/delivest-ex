defmodule DelivestWeb.Staff.ReceiptLive.Index do
  use DelivestWeb, :live_view
  import DelivestWeb.Staff.FoundationComponents, only: [filter_bar: 1]

  alias Delivest.Fiscal
  alias Delivest.Fiscal.Receipt

  on_mount {DelivestWeb.Hooks.Permission, "orders.read"}

  @filters ~w(problem pending wait done fail)

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, page_title: gettext("Receipts"))}

  @impl true
  def handle_params(params, _url, socket) do
    status = if params["status"] in @filters, do: String.to_existing_atom(params["status"])

    query =
      params
      |> Map.take(~w(status search from to page page_size))
      |> Map.filter(fn {_key, value} -> is_binary(value) end)

    {receipts, pagination} = Fiscal.list_branch_page(socket.assigns.current_branch.id, query)

    {:noreply,
     assign(socket,
       status: status,
       query: query,
       pagination: pagination,
       receipts: receipts
     )}
  end

  @impl true
  def handle_event("filter", params, socket) do
    query =
      socket.assigns.query
      |> Map.merge(Map.take(params, ~w(search from to)))
      |> Map.put("page", 1)

    {:noreply, push_patch(socket, to: receipt_path(socket.assigns, query))}
  end

  def handle_event("update_page_size", %{"page_size" => size}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         receipt_path(
           socket.assigns,
           Map.merge(socket.assigns.query, %{"page_size" => size, "page" => 1})
         )
     )}
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header
      title={gettext("Receipts")}
      subtitle={gettext("Fiscal receipts of the branch. Find the ones not issued during the shift.")}
    />
    """
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, filters: filters())

    ~H"""
    <div id="receipts-page" class="space-y-6">
      <p
        :if={Delivest.Gateway.crm?(@current_branch, :receipts)}
        id="receipts-external-owner"
        role="status"
        class="alert alert-info"
      >
        {gettext(
          "New receipts are managed by the connected system. Existing fiscal obligations remain visible here."
        )}
      </p>
      <div class="tabs tabs-box w-fit">
        <.link
          :for={{value, label} <- @filters}
          id={"receipts-filter-#{value || "all"}"}
          patch={
            receipt_path(
              assigns,
              Map.merge(@query, %{"status" => value && to_string(value), "page" => 1})
            )
          }
          class={["tab", @status == value && "tab-active"]}
        >
          {label}
        </.link>
      </div>

      <.filter_bar
        id="receipts-filter"
        query={@query["search"] || ""}
        query_name="search"
        reset_path={receipt_path(assigns, %{})}
        event="filter"
        active={@status != nil or @query["from"] not in [nil, ""] or @query["to"] not in [nil, ""]}
      >
        <:filter>
          <div>
            <label for="receipts-from" class="block text-sm font-medium">{gettext("From")}</label>
            <input
              id="receipts-from"
              name="from"
              type="date"
              value={@query["from"]}
              class="input input-bordered"
            />
          </div>
          <div>
            <label for="receipts-to" class="block text-sm font-medium">{gettext("To")}</label>
            <input
              id="receipts-to"
              name="to"
              type="date"
              value={@query["to"]}
              class="input input-bordered"
            />
          </div>
        </:filter>
      </.filter_bar>

      <.card>
        <.table
          id="receipts"
          rows={@receipts}
          row_id={fn {receipt, _number} -> "receipt-row-#{receipt.id}" end}
          empty_title={if @query == %{}, do: gettext("No receipts"), else: gettext("Nothing found")}
        >
          <:col :let={{receipt, number}} label={gettext("Order")}>
            <.link
              navigate={~p"/staff/b/#{@current_branch}/orders/#{receipt.order_id}"}
              class="link link-primary"
            >
              {number}
            </.link>
          </:col>
          <:col :let={{receipt, _number}} label={gettext("Receipt")} secondary>
            {kind(receipt.kind)}
          </:col>
          <:col :let={{receipt, _number}} label={gettext("Amount")} numeric>
            <span class="tabular-nums">{Delivest.Money.format(receipt.amount)}</span>
          </:col>
          <:col :let={{receipt, _number}} label={gettext("Status")}>
            <span class={["badge badge-sm", badge(receipt.status)]}>{status(receipt.status)}</span>
            <a
              :if={url = Receipt.ofd_url(receipt)}
              href={url}
              target="_blank"
              class="link text-xs ml-2"
            >
              {gettext("OFD")}
            </a>
            <div :if={receipt.status == :fail} class="text-xs text-error">{receipt.error}</div>
          </:col>
          <:col :let={{receipt, _number}} label={gettext("Created at")}>
            <span class="text-sm text-base-content/70">
              {receipt.inserted_at
              |> Delivest.LocalTime.local(@current_branch)
              |> Calendar.strftime("%d.%m %H:%M")}
            </span>
          </:col>
        </.table>
        <p class="px-3 pt-3 text-sm text-base-content/70">
          {gettext("%{count} receipts", count: @pagination.total)}
        </p>
        <.pagination
          id="receipts-page-size"
          meta={pagination_meta(@pagination)}
          path_fn={fn overrides -> receipt_path(assigns, Map.merge(@query, overrides)) end}
          page_sizes={[25, 50, 100]}
        />
      </.card>
    </div>
    """
  end

  defp receipt_path(assigns, params) do
    params = Map.reject(params, fn {_key, value} -> value in [nil, "", []] end)
    ~p"/staff/b/#{assigns.current_branch}/finance/receipts?#{params}"
  end

  defp pagination_meta(page) do
    %Flop.Meta{
      current_page: page.page,
      page_size: page.page_size,
      total_pages: page.pages,
      total_count: page.total
    }
  end

  defp filters,
    do: [
      {nil, gettext("All")},
      {:problem, gettext("Need attention")},
      {:pending, gettext("Sending")},
      {:wait, gettext("Processing")},
      {:done, gettext("Issued")},
      {:fail, gettext("Failed")}
    ]

  defp kind(:sell), do: gettext("Sale receipt")
  defp kind(:sell_refund), do: gettext("Refund receipt")
  defp kind(_kind), do: gettext("Correction receipt")

  defp status(:pending), do: gettext("Sending")
  defp status(:wait), do: gettext("Processing")
  defp status(:done), do: gettext("Issued")
  defp status(:fail), do: gettext("Failed")

  defp badge(:done), do: "badge-success"
  defp badge(:fail), do: "badge-error"
  defp badge(_status), do: "badge-warning"
end
