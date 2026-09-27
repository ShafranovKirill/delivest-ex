defmodule DelivestWeb.Staff.OrderLive.Components.DetailsComponent do
  use DelivestWeb, :html

  def render_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="order-details-form"
      phx-change="validate_order"
      phx-submit="save_order"
      class="space-y-3"
    >
      <div class="form-control">
        <label class="label text-xs font-bold uppercase text-base-content/60 p-0 mb-1">
          {gettext("Customer Info")}
        </label>
        <div class="space-y-2">
          <.input
            field={@form[:customer_phone]}
            type="text"
            label={gettext("Phone")}
            placeholder="+79991112233"
            maxlength="12"
          />
          <.input
            field={@form[:customer_name]}
            type="text"
            label={gettext("Client Name")}
            maxlength="100"
          />
        </div>
      </div>

      <div class="divider text-xs font-bold uppercase text-base-content/40 my-2">
        {gettext("Options")}
      </div>

      <.input
        field={@form[:fulfillment_type]}
        type="select"
        label={gettext("Fulfillment Type")}
        options={[
          {gettext("Dine In"), "dine_in"},
          {gettext("Delivery"), "delivery"},
          {gettext("Pickup"), "pickup"}
        ]}
      />

      <.input
        field={@form[:payment_method]}
        type="select"
        label={gettext("Payment Method")}
        options={[
          {gettext("Cash"), "cash"},
          {gettext("Card Offline"), "card_offline"}
        ]}
      />

      <% fulfillment_type = Ecto.Changeset.get_field(@form.source, :fulfillment_type) %>
      <%= if to_string(fulfillment_type) == "delivery" do %>
        <div class="p-3 bg-base-200/50 rounded-box border border-base-300 space-y-2">
          <span class="text-xs font-bold">{gettext("Delivery Address")}</span>
          <.inputs_for :let={address_form} field={@form[:address]}>
            <.input
              field={address_form[:city]}
              type="text"
              label={gettext("City")}
              maxlength="100"
              required
            />
            <.input
              field={address_form[:street]}
              type="text"
              label={gettext("Street")}
              maxlength="150"
              required
            />
            <.input
              field={address_form[:house]}
              type="text"
              label={gettext("House")}
              maxlength="20"
              required
            />

            <div class="grid grid-cols-3 gap-2">
              <.input
                field={address_form[:entrance]}
                type="text"
                label={gettext("Entrance")}
                maxlength="10"
              />
              <.input
                field={address_form[:floor]}
                type="text"
                label={gettext("Floor")}
                maxlength="10"
              />
              <.input
                field={address_form[:apartment]}
                type="text"
                label={gettext("Apartment")}
                maxlength="20"
              />
            </div>
          </.inputs_for>
        </div>
      <% end %>

      <.input
        field={@form[:comment]}
        type="textarea"
        label={gettext("Comment")}
        rows={2}
        maxlength="500"
      />
    </.form>
    """
  end
end
