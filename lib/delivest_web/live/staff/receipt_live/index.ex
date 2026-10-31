defmodule DelivestWeb.Staff.ReceiptLive.Index do
  use DelivestWeb, :live_view

  on_mount {DelivestWeb.Hooks.GatewayArea, :receipts}

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

    {:noreply,
     assign(socket,
       status: status,
       receipts: Fiscal.list_branch(socket.assigns.current_branch.id, status)
     )}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, filters: filters())

    ~H"""
    <div id="receipts-page" class="space-y-4 py-4 sm:p-6 max-w-6xl">
      <.page_header
        title={gettext("Receipts")}
        subtitle={
          gettext("Fiscal receipts of the branch. Find the ones not issued during the shift.")
        }
      />

      <div class="tabs tabs-box w-fit">
        <.link
          :for={{value, label} <- @filters}
          id={"receipts-filter-#{value || "all"}"}
          patch={~p"/staff/b/#{@current_branch}/finance/receipts?#{(value && [status: value]) || []}"}
          class={["tab", @status == value && "tab-active"]}
        >
          {label}
        </.link>
      </div>

      <.card class="overflow-x-auto">
        <table class="table">
          <thead>
            <tr>
              <th>{gettext("Order")}</th>
              <th>{gettext("Receipt")}</th>
              <th class="text-right">{gettext("Amount")}</th>
              <th>{gettext("Status")}</th>
              <th>{gettext("Created")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{receipt, number} <- @receipts} id={"receipt-row-#{receipt.id}"}>
              <td>
                <.link
                  navigate={~p"/staff/b/#{@current_branch}/orders/#{receipt.order_id}"}
                  class="link link-primary"
                >
                  {number}
                </.link>
              </td>
              <td>{kind(receipt.kind)}</td>
              <td class="text-right tabular-nums">{Delivest.Money.format(receipt.amount)}</td>
              <td>
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
              </td>
              <td class="text-sm text-base-content/70">
                {receipt.inserted_at
                |> Delivest.LocalTime.local(@current_branch)
                |> Calendar.strftime("%d.%m %H:%M")}
              </td>
            </tr>
          </tbody>
        </table>
        <.empty_state :if={@receipts == []} title={gettext("No receipts")} class="py-12" />
      </.card>
    </div>
    """
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
