defmodule DelivestWeb.Staff.ClientLive.Navigation do
  use DelivestWeb, :html

  attr :active, :atom, required: true

  def tabs(assigns) do
    ~H"""
    <div class="tabs">
      <.link navigate={~p"/staff/clients"} class="tab" aria-current={@active == :clients && "page"}>
        {gettext("Clients")}
      </.link>
      <.link navigate={~p"/staff/segments"} class="tab" aria-current={@active == :segments && "page"}>
        {gettext("Segments")}
      </.link>
    </div>
    """
  end
end
