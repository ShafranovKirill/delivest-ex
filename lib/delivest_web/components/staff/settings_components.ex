defmodule DelivestWeb.Staff.SettingsComponents do
  use Phoenix.Component

  import DelivestWeb.CoreComponents, only: [icon: 1]

  slot :inner_block, required: true

  def settings_cards(assigns) do
    ~H"""
    <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil

  def settings_card(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class="card bg-base-100 border border-base-300 hover:border-primary transition-colors"
    >
      <div class="card-body flex-row items-start gap-3">
        <div class="bg-primary/10 text-primary rounded-field p-2 shrink-0">
          <.icon name={@icon} class="size-5" />
        </div>
        <div class="min-w-0 space-y-1">
          <h3 class="font-bold">{@title}</h3>
          <p :if={@description} class="text-sm text-base-content/60">{@description}</p>
        </div>
      </div>
    </.link>
    """
  end
end
