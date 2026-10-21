defmodule DelivestWeb.Staff.OrderLive.Components.TabsComponent do
  use DelivestWeb, :html

  attr :active_tab, :atom, required: true
  attr :quantity, :integer, required: true
  attr :cart_label, :string, required: true
  attr :details_label, :string, required: true
  attr :compact, :boolean, default: false

  def render_tabs(assigns) do
    ~H"""
    <div class="tabs tabs-boxed grid grid-cols-2">
      <button
        type="button"
        class={["tab text-xs", @active_tab == :cart && "tab-active font-bold"]}
        phx-click="switch_tab"
        phx-value-tab="cart"
      >
        <.icon name="hero-shopping-bag" class={["size-4", if(@compact, do: "mr-1", else: "mr-1.5")]} />
        {@cart_label}
        <span
          :if={@quantity > 0}
          class={[
            "badge badge-primary ml-1 font-mono",
            if(@compact, do: "badge-xs", else: "badge-sm")
          ]}
        >
          {@quantity}
        </span>
      </button>
      <button
        type="button"
        class={["tab text-xs", @active_tab == :details && "tab-active font-bold"]}
        phx-click="switch_tab"
        phx-value-tab="details"
      >
        <.icon
          name="hero-document-text"
          class={["size-4", if(@compact, do: "mr-1", else: "mr-1.5")]}
        />
        {@details_label}
      </button>
    </div>
    """
  end
end
