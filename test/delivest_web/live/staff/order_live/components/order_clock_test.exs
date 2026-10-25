defmodule DelivestWeb.Staff.OrderLive.Components.OrderClockTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Delivest.Oms.Order
  alias DelivestWeb.Staff.OrderLive.Components.OrderClock

  @order %Order{
    id: Ecto.UUID.generate(),
    inserted_at: ~U[2026-10-25 10:00:00Z],
    fulfillment_type: :delivery
  }

  test "the clock keeps the minutes placeholder for the browser without logging errors" do
    log =
      capture_log(fn ->
        for status <- [:created, :preparing] do
          html =
            render_component(&OrderClock.order_clock/1,
              order: @order,
              status: status,
              delivery_minutes: 60
            )

          assert html =~ "%{minutes}"
        end
      end)

    refute log =~ "missing Gettext bindings"
  end
end
