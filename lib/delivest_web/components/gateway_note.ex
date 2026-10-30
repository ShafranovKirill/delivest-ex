defmodule DelivestWeb.GatewayNote do
  use DelivestWeb, :html

  alias Delivest.Gateway

  attr :branch, :map, default: nil

  def gateway_badge(%{branch: nil} = assigns), do: ~H""

  def gateway_badge(assigns) do
    assigns = assign(assigns, :mode, Gateway.mode(assigns.branch))

    ~H"""
    <.link
      :if={@mode.provider}
      id="gateway-badge"
      navigate={~p"/staff/b/#{@branch}/integrations"}
      class="hidden items-center gap-1.5 rounded-field bg-info/15 px-2 py-1 text-xs font-semibold text-info md:flex"
    >
      <.icon name="hero-arrows-right-left" class="size-4" />
      {badge_text(@mode)}
    </.link>
    """
  end

  defp badge_text(%{name: name, areas: %{menu: :crm}}),
    do: gettext("Gateway: %{crm}, menu from CRM", crm: name)

  defp badge_text(%{name: name}), do: gettext("Gateway: %{crm}", crm: name)

  attr :branch, :map, required: true

  def gateway_summary(assigns) do
    assigns = assign(assigns, :mode, Gateway.mode(assigns.branch))

    ~H"""
    <section :if={@mode.provider} id="gateway-summary" class="space-y-3">
      <div>
        <h2 class="font-bold">{gettext("Gateway mode: %{crm}", crm: @mode.name)}</h2>
        <p class="text-sm text-base-content/60">
          {gettext("The branch hands orders to the CRM. Who runs what:")}
        </p>
      </div>
      <ul class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
        <li
          :for={area <- Gateway.areas()}
          id={"gateway-area-#{area}"}
          class="flex items-center justify-between rounded-box border border-base-300 bg-base-100 px-4 py-2 text-sm"
        >
          <span>{area_label(area)}</span>
          <span class={[
            "badge badge-sm",
            @mode.areas[area] == :crm && "badge-info",
            @mode.areas[area] == :own && "badge-ghost"
          ]}>
            {if @mode.areas[area] == :crm, do: @mode.name, else: "Delivest"}
          </span>
        </li>
      </ul>
    </section>
    """
  end

  defp area_label(:kitchen), do: gettext("Kitchen")
  defp area_label(:statuses), do: gettext("Order statuses")
  defp area_label(:pos), do: gettext("POS")
  defp area_label(:couriers), do: gettext("Couriers and deliveries")
  defp area_label(:receipts), do: gettext("Receipts")
  defp area_label(:menu), do: gettext("Menu")
  defp area_label(:stops), do: gettext("Stop list")

  attr :name, :string, required: true
  attr :area, :atom, required: true
  attr :branch, :map, default: nil

  def gateway_note(assigns) do
    ~H"""
    <div
      id="gateway-note"
      class="mx-auto my-16 max-w-xl rounded-box border border-base-300 bg-base-100 p-8 text-center"
    >
      <.icon name="hero-arrows-right-left" class="mx-auto size-10 text-base-content/40" />
      <h2 class="mt-4 text-xl font-semibold">
        {gettext("Managed in %{crm}", crm: @name)}
      </h2>
      <p class="mt-2 text-base-content/60">{area_text(@area, @name)}</p>
      <.link
        :if={@branch}
        navigate={~p"/staff/b/#{@branch}/integrations"}
        class="btn btn-sm btn-ghost mt-6"
      >
        {gettext("Integration settings")}
      </.link>
    </div>
    """
  end

  defp area_text(:couriers, name),
    do:
      gettext("Delivery of orders is handled by %{crm}, couriers are not assigned here.",
        crm: name
      )

  defp area_text(:receipts, name),
    do: gettext("Receipts are printed on the cash desk of %{crm}.", crm: name)

  defp area_text(:pos, name), do: gettext("Sales go through the POS of %{crm}.", crm: name)
  defp area_text(:kitchen, name), do: gettext("The kitchen works in %{crm}.", crm: name)
  defp area_text(_area, name), do: gettext("This section is managed in %{crm}.", crm: name)
end
