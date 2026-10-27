defmodule Delivest.Oms.OrderStatusTest do
  use ExUnit.Case, async: true

  alias Delivest.Oms.{Order, OrderStatus}
  alias Delivest.Oms.Order.{ChannelSync, CrmSync}

  defp crm_order(remote, channel \\ nil),
    do: %Order{
      status: :crm,
      crm: %CrmSync{provider: "frontpad", status: "sent", remote_status: remote},
      channel:
        channel && %ChannelSync{provider: "yandex_eda", external_id: "1", remote_status: channel}
    }

  test "the kitchen status comes from the crm" do
    assert OrderStatus.current(crm_order(nil)) == :accepted
    assert OrderStatus.current(crm_order("preparing")) == :preparing
  end

  test "the channel only moves the order forward or cancels it" do
    assert OrderStatus.current(crm_order("ready", "delivering")) == :delivering
    assert OrderStatus.current(crm_order("completed", "delivering")) == :completed
    assert OrderStatus.current(crm_order("preparing", "cancelled")) == :cancelled
  end

  test "forward? allows cancelling from anywhere and nothing backwards" do
    assert OrderStatus.forward?(:ready, :cancelled)
    assert OrderStatus.forward?(nil, :created)
    refute OrderStatus.forward?(:ready, :preparing)
  end

  test "a channel cancellation needs a manual cancel in the crm" do
    assert Delivest.Integrations.Crm.manual_cancel_required?(crm_order("preparing", "cancelled"))
    refute Delivest.Integrations.Crm.manual_cancel_required?(crm_order("cancelled", "cancelled"))
    refute Delivest.Integrations.Crm.manual_cancel_required?(crm_order("preparing"))
  end
end
