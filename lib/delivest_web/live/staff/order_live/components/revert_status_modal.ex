defmodule DelivestWeb.Staff.OrderLive.Components.RevertStatusModal do
  use DelivestWeb, :html

  alias Delivest.Oms.Order

  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  attr :order, :map, default: nil

  def revert_status_modal(assigns) do
    ~H"""
    <.modal
      id="revert-status-modal"
      show={@order != nil}
      title={
        @order && gettext("Revert the status of order #%{number}", number: Order.short_number(@order))
      }
      on_cancel={JS.push("dismiss_revert")}
    >
      <.form
        :if={@order}
        for={%{}}
        as={:revert}
        id="revert-status-form"
        phx-submit="confirm_revert"
        class="space-y-3 pt-3"
      >
        <p class="text-sm text-base-content/70">
          {gettext(
            "The last step «%{status}» is removed. The reason goes to the order history and the log.",
            status: OrderHelpers.status_label(@order.status)
          )}
        </p>
        <textarea
          name="revert[reason]"
          rows="3"
          maxlength="300"
          required
          placeholder={gettext("Why is the status reverted?")}
          class="textarea textarea-bordered w-full"
        ></textarea>
        <div class="modal-action">
          <button type="button" class="btn btn-ghost btn-sm" phx-click="dismiss_revert">
            {gettext("Keep the status")}
          </button>
          <button type="submit" class="btn btn-warning btn-sm">
            <.icon name="hero-arrow-uturn-left" class="size-4" /> {gettext("Revert")}
          </button>
        </div>
      </.form>
    </.modal>
    """
  end
end
