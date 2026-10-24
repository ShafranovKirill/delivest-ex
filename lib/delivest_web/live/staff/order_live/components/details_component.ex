defmodule DelivestWeb.Staff.OrderLive.Components.DetailsComponent do
  use DelivestWeb, :html

  import DelivestWeb.Staff.OrderLive.Components.Segmented, only: [segmented: 1]
  import DelivestWeb.Staff.OrderLive.Components.ClientPanel, only: [client_panel: 1]

  attr :form, :any, required: true
  attr :known_client, :any, required: true
  attr :timing, :string, required: true

  def render_form(assigns) do
    assigns =
      assign(assigns,
        fulfillment: to_string(Ecto.Changeset.get_field(assigns.form.source, :fulfillment_type)),
        payment: to_string(Ecto.Changeset.get_field(assigns.form.source, :payment_method))
      )

    ~H"""
    <.form
      for={@form}
      id="order-details-form"
      phx-change="validate_order"
      phx-submit="save_order"
      class="space-y-5"
    >
      <.section title={gettext("Client")}>
        <.client_panel form={@form} known_client={@known_client} />
      </.section>

      <.section title={gettext("Fulfillment")}>
        <.segmented
          id="order-fulfillment"
          name={@form[:fulfillment_type].name}
          value={@fulfillment}
          options={[
            {"dine_in", gettext("Dine In"), "hero-building-storefront"},
            {"pickup", gettext("Pickup"), "hero-shopping-bag"},
            {"delivery", gettext("Delivery"), "hero-truck"}
          ]}
        />

        <div :if={@fulfillment == "delivery"} class="mt-3 space-y-2">
          <div :if={@known_client && @known_client.addresses != []} class="flex flex-wrap gap-1.5">
            <button
              :for={address <- @known_client.addresses}
              type="button"
              id={"use-address-#{address.id}"}
              phx-click="use_address"
              phx-value-id={address.id}
              class="btn btn-xs btn-outline rounded-full max-w-full"
            >
              <.icon name="hero-map-pin" class="size-3.5" />
              <span class="truncate">{address.street}, {address.house}</span>
            </button>
          </div>
          <.inputs_for :let={address_form} field={@form[:address]}>
            <div class="grid grid-cols-6 gap-2">
              <div class="col-span-6 sm:col-span-2">
                <.input
                  field={address_form[:city]}
                  type="text"
                  label={gettext("City")}
                  maxlength="100"
                />
              </div>
              <div class="col-span-4 sm:col-span-3">
                <.input
                  field={address_form[:street]}
                  type="text"
                  label={gettext("Street")}
                  maxlength="150"
                />
              </div>
              <div class="col-span-2 sm:col-span-1">
                <.input
                  field={address_form[:house]}
                  type="text"
                  label={gettext("House")}
                  maxlength="20"
                />
              </div>
              <div class="col-span-2">
                <.input
                  field={address_form[:entrance]}
                  type="text"
                  label={gettext("Entrance")}
                  maxlength="10"
                />
              </div>
              <div class="col-span-2">
                <.input
                  field={address_form[:floor]}
                  type="text"
                  label={gettext("Floor")}
                  maxlength="10"
                />
              </div>
              <div class="col-span-2">
                <.input
                  field={address_form[:apartment]}
                  type="text"
                  label={gettext("Apartment")}
                  maxlength="20"
                />
              </div>
            </div>
          </.inputs_for>
        </div>
      </.section>

      <.section title={gettext("Time")}>
        <.segmented
          id="order-timing"
          name="order[timing]"
          value={@timing}
          options={[
            {"asap", gettext("Right away"), "hero-bolt"},
            {"scheduled", gettext("By time"), "hero-calendar"}
          ]}
        />
        <div :if={@timing == "scheduled"} class="mt-2">
          <.input
            field={@form[:cook_by]}
            type="datetime-local"
            label={gettext("Prepare by")}
            max={Date.to_iso8601(Date.add(Date.utc_today(), 30)) <> "T23:59:59"}
          />
        </div>
      </.section>

      <.section title={gettext("Payment")}>
        <.segmented
          id="order-payment"
          name={@form[:payment_method].name}
          value={@payment}
          options={[
            {"cash", gettext("Cash"), "hero-banknotes"},
            {"card_offline", gettext("Card Offline"), "hero-credit-card"}
          ]}
        />
      </.section>

      <.input
        field={@form[:comment]}
        type="textarea"
        label={gettext("Comment")}
        rows={2}
        maxlength="500"
        phx-debounce="300"
      />
    </.form>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <section>
      <h3 class="mb-2 text-xs font-bold uppercase tracking-wide text-base-content/50">{@title}</h3>
      {render_slot(@inner_block)}
    </section>
    """
  end
end
