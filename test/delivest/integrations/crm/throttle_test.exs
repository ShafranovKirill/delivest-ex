defmodule Delivest.Integrations.Crm.ThrottleTest do
  use ExUnit.Case, async: true

  alias Delivest.Integrations.Crm.Throttle

  test "spaces calls sharing a key by the interval" do
    key = make_ref()
    started = System.monotonic_time(:millisecond)

    Throttle.run({key, 100}, fn -> :ok end)
    assert :done = Throttle.run({key, 100}, fn -> :done end)

    assert System.monotonic_time(:millisecond) - started >= 100
  end

  test "runs at once without a limit" do
    assert :ok = Throttle.run(nil, fn -> :ok end)
  end
end
