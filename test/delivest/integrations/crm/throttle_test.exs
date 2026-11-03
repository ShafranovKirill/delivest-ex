defmodule Delivest.Integrations.Crm.ThrottleTest do
  use ExUnit.Case, async: true

  alias Delivest.Integrations.Crm.Throttle

  test "spaces calls sharing a key by the interval" do
    key = make_ref()

    assert :ok = Throttle.run({key, 100}, fn -> :ok end)

    assert {:error, {:throttled, wait_ms}} = Throttle.run({key, 100}, fn -> :done end)
    assert wait_ms > 0 and wait_ms <= 100
  end

  test "a call after the interval runs at once" do
    key = make_ref()

    assert :ok = Throttle.run({key, 0}, fn -> :ok end)
    assert :done = Throttle.run({key, 0}, fn -> :done end)
  end

  test "different keys do not wait for each other" do
    assert :ok = Throttle.run({make_ref(), 1000}, fn -> :ok end)
    assert :ok = Throttle.run({make_ref(), 1000}, fn -> :ok end)
  end

  test "runs at once without a limit" do
    assert :ok = Throttle.run(nil, fn -> :ok end)
  end

  test "waits for the next slot when the caller cannot be rescheduled" do
    key = make_ref()

    assert :ok = Throttle.run({key, 50}, fn -> :ok end)
    assert :done = Throttle.run_wait({key, 50}, fn -> :done end)
  end

  test "a throttled call snoozes the worker instead of waiting" do
    order = %Delivest.Oms.Order{crm: %{provider: "frontpad"}}

    assert Delivest.Integrations.Crm.classify_error(order, {:throttled, 1_200}) ==
             {:snooze, 2}
  end
end
