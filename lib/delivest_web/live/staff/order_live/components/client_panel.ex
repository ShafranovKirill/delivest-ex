defmodule DelivestWeb.Staff.OrderLive.Components.ClientPanel do
  use DelivestWeb, :html

  alias DelivestWeb.Staff.OrderLive.KnownClient

  attr :form, :any, required: true
  attr :known_client, :any, required: true

  def client_panel(assigns) do
    assigns =
      assign(assigns, valid_phone?: KnownClient.valid_phone?(assigns.form[:customer_phone].value))

    ~H"""
    <section class="space-y-2">
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
        <.input
          field={@form[:customer_phone]}
          type="tel"
          label={gettext("Phone")}
          placeholder="+79991112233"
          maxlength="12"
          autocomplete="off"
          phx-debounce="300"
        />
        <.input
          field={@form[:customer_name]}
          type="text"
          label={gettext("Client Name")}
          maxlength="100"
          phx-debounce="300"
        />
      </div>

      <div
        :if={@known_client}
        id="known-client"
        class="flex items-center gap-2 rounded-box bg-success/10 px-3 py-2 text-sm"
      >
        <.icon name="hero-user-circle" class="size-5 text-success shrink-0" />
        <span class="min-w-0 truncate font-medium">
          {@known_client.client.name || gettext("Client")}
        </span>
        <span class="text-base-content/60 shrink-0">
          · {ngettext("%{count} order", "%{count} orders", @known_client.orders_count)}
        </span>
      </div>
      <p
        :if={!@known_client and @valid_phone?}
        id="new-client"
        class="flex items-center gap-2 rounded-box bg-base-200 px-3 py-2 text-sm text-base-content/70"
      >
        <.icon name="hero-sparkles" class="size-4" /> {gettext("New client")}
      </p>
    </section>
    """
  end
end
