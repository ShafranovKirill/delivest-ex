defmodule DelivestWeb.Staff.DeliveryLive.Index do
  use DelivestWeb, :live_view

  import DelivestWeb.Staff.SettingsComponents

  on_mount {DelivestWeb.Hooks.Permission, "delivery.read"}

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, page_title: gettext("Delivery"))}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6 max-w-6xl">
      <.page_header title={gettext("Delivery")} />

      <.settings_cards>
        <.settings_card
          id="delivery-zones-card"
          navigate={~p"/staff/b/#{@current_branch}/delivery/zones"}
          icon="hero-map"
          title={gettext("Delivery zones")}
          description={gettext("Delivery price, minimum order and zones on the map.")}
        />
        <.settings_card
          id="delivery-couriers-card"
          navigate={~p"/staff/b/#{@current_branch}/delivery/couriers"}
          icon="hero-truck"
          title={gettext("Branch couriers")}
          description={gettext("Who delivers the orders and when the courier search starts.")}
        />
      </.settings_cards>
    </div>
    """
  end
end
