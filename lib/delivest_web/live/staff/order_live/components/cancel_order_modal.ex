defmodule DelivestWeb.Staff.OrderLive.Components.CancelOrderModal do
  use DelivestWeb, :html

  alias Delivest.Oms.Order

  alias DelivestWeb.Staff.OrderLive.CancelReasons

  attr :order, :map, default: nil

  def cancel_order_modal(assigns) do
    assigns = assign(assigns, reasons: CancelReasons.selectable())

    ~H"""
    <.modal
      id="cancel-order-modal"
      show={@order != nil}
      title={@order && gettext("Cancel order #%{number}", number: Order.short_number(@order))}
      on_cancel={JS.push("dismiss_cancel")}
    >
      <.form
        :if={@order}
        for={%{}}
        as={:cancel}
        id="cancel-order-form"
        phx-submit="confirm_cancel"
        class="space-y-3 pt-3"
      >
        <p class="text-sm text-base-content/70">{gettext("Why is the order cancelled?")}</p>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
          <label
            :for={reason <- @reasons}
            class="flex items-center gap-2 rounded-box border border-base-300 px-3 py-2.5 cursor-pointer has-checked:border-error has-checked:bg-error/5"
          >
            <input
              type="radio"
              name="cancel[reason]"
              value={reason}
              required
              class="radio radio-sm radio-error"
            />
            <span class="text-sm">{CancelReasons.label(reason)}</span>
          </label>
        </div>
        <textarea
          name="cancel[note]"
          rows="2"
          maxlength="300"
          placeholder={gettext("Comment, if needed")}
          class="textarea textarea-bordered w-full"
        ></textarea>
        <div class="modal-action">
          <button type="button" class="btn btn-ghost btn-sm" phx-click="dismiss_cancel">
            {gettext("Keep the order")}
          </button>
          <button type="submit" class="btn btn-error btn-sm">{gettext("Cancel order")}</button>
        </div>
      </.form>
    </.modal>
    """
  end
end
