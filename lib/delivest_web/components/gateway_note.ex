defmodule DelivestWeb.GatewayNote do
  use DelivestWeb, :html

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
