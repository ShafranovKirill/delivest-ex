defmodule DelivestWeb.Staff.OrderLive.Components.OrderCustomerModal do
  use DelivestWeb, :html

  alias Delivest.Identity
  alias Delivest.Oms.Orders
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  @history_limit 20

  def load(staff, branch, order) do
    customer =
      cond do
        is_nil(order.client_id) or order.guest_session_access ->
          guest(branch, order)

        true ->
          case Identity.get_client(staff, order.client_id) do
            {:ok, client} -> registered(staff, client, order)
            {:error, _reason} -> snapshot(branch, order)
          end
      end

    Map.put(customer, :can_see_finance, Identity.can?(staff, "finance.read"))
  end

  defp registered(staff, client, order) do
    branches = Map.new(Identity.list_branch_for_staff(staff), &{&1.id, &1})

    %{
      client: client,
      name: client.name || order.customer_name,
      phone: client.phone,
      extension: nil,
      branches: branches,
      orders: Orders.list_client_orders(client.id, Map.keys(branches), @history_limit)
    }
  end

  defp guest(branch, %{customer_phone: phone} = order) when is_binary(phone) and phone != "" do
    orders = Orders.list_guest_orders(branch.id, phone, order.customer_phone_ext, @history_limit)
    %{snapshot(branch, order) | orders: orders}
  end

  defp guest(branch, order), do: snapshot(branch, order)

  defp snapshot(branch, order) do
    %{
      client: nil,
      name: order.customer_name,
      phone: order.customer_phone,
      extension: order.customer_phone_ext,
      branches: %{branch.id => branch},
      orders: [order]
    }
  end

  attr :customer, :map, required: true
  attr :current_branch, :map, required: true
  attr :return_query, :map, required: true

  def customer_modal(assigns) do
    ~H"""
    <div
      id="order-customer-modal"
      role="dialog"
      aria-modal="true"
      aria-labelledby="order-customer-modal-title"
      class="modal modal-open z-[110]"
      phx-window-keydown={JS.push("hide_customer")}
      phx-key="escape"
      phx-mounted={JS.focus_first(to: "#order-customer-modal-focus")}
      phx-remove={JS.pop_focus()}
    >
      <.focus_wrap
        id="order-customer-modal-focus"
        class="modal-box max-h-[85dvh] max-w-2xl space-y-4 border border-base-300"
      >
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <h2 id="order-customer-modal-title" class="break-words text-lg font-bold">
              {@customer.name || gettext("Customer")}
            </h2>
            <p :if={@customer.phone} class="font-mono text-sm text-base-content/70">
              {OrderHelpers.format_phone(@customer.phone, @customer.extension)}
            </p>
          </div>
          <button
            id="order-customer-close"
            type="button"
            class="btn btn-ghost btn-sm btn-square"
            aria-label={gettext("Close")}
            phx-click="hide_customer"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
        <div :if={@customer.client} class="flex flex-wrap items-center gap-x-3 gap-y-2 text-sm">
          <span :if={@customer.client.status == :blocked} class="badge badge-error badge-sm">
            {gettext("Blocked")}
          </span>
          <span class="text-base-content/60">
            {gettext("Client since")} {OrderHelpers.local_datetime(@customer.client.inserted_at)}
          </span>
          <.link navigate={~p"/staff/clients/#{@customer.client.id}"} class="link link-hover ml-auto">
            {gettext("Open client card")}
          </.link>
          <p :if={@customer.client.operator_note} class="basis-full break-words text-base-content/80">
            {@customer.client.operator_note}
          </p>
        </div>

        <section aria-labelledby="order-customer-history-title">
          <h3 id="order-customer-history-title" class="mb-2 font-semibold">
            {gettext("Order history")}
          </h3>
          <p :if={@customer.orders == []} class="text-sm text-base-content/60">
            {gettext("No orders yet")}
          </p>
          <ul id="order-customer-history" class="divide-y divide-base-200">
            <li :for={order <- @customer.orders} id={"customer-history-order-#{order.id}"}>
              <.history_order
                order={order}
                branch={@customer.branches[order.branch_id]}
                current_branch={@current_branch}
                return_query={@return_query}
                can_see_finance={@customer.can_see_finance}
              />
            </li>
          </ul>
        </section>
      </.focus_wrap>
      <div class="modal-backdrop bg-black/50" phx-click="hide_customer"></div>
    </div>
    """
  end

  attr :order, :map, required: true
  attr :branch, :map, required: true
  attr :current_branch, :map, required: true
  attr :return_query, :map, required: true
  attr :can_see_finance, :boolean, required: true

  defp history_order(assigns) do
    assigns =
      if assigns.branch.id == assigns.current_branch.id do
        assign(assigns,
          patch:
            ~p"/staff/b/#{assigns.branch}/orders/#{assigns.order.id}?#{assigns.return_query}",
          navigate: nil
        )
      else
        assign(assigns,
          patch: nil,
          navigate: ~p"/staff/b/#{assigns.branch}/orders/#{assigns.order.id}"
        )
      end

    ~H"""
    <.link
      patch={@patch}
      navigate={@navigate}
      class="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-field px-1 py-2.5 text-sm hover:bg-base-200"
    >
      <span class="font-mono font-semibold">#{Delivest.Oms.Order.short_number(@order)}</span>
      <span class={["badge badge-sm border", OrderHelpers.status_color(@order.status)]}>
        {OrderHelpers.status_label(@order.status)}
      </span>
      <span class="text-base-content/70">{@branch.name} · {OrderHelpers.fulfillment_label(
        @order.fulfillment_type
      )}</span>
      <time class="text-base-content/60" datetime={DateTime.to_iso8601(@order.inserted_at)}>
        {OrderHelpers.local_datetime(@order.inserted_at)}
      </time>
      <span :if={@can_see_finance} class="ml-auto font-mono font-medium">
        {OrderHelpers.money(@order.total_amount)}
      </span>
      <.icon name="hero-chevron-right" class="size-4 shrink-0 text-base-content/50" />
    </.link>
    """
  end
end
