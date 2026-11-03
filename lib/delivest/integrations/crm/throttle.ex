defmodule Delivest.Integrations.Crm.Throttle do
  @cache :rate_limit_cache

  def run(nil, fun), do: fun.()

  def run({key, interval_ms}, fun) do
    now = System.monotonic_time(:millisecond)

    case reserve(key, interval_ms, now) do
      :ok -> fun.()
      {:wait, slot} -> {:error, {:throttled, max(slot - now, 0)}}
    end
  end

  @doc """
  Waits for the next free slot instead of returning a throttling error.

  Only for callers that cannot reschedule themselves, such as a health check
  started by hand. Order delivery and commands use `run/2` and snooze the Oban
  job instead of occupying a queue slot while waiting.
  """
  def run_wait(nil, fun), do: fun.()

  def run_wait({key, interval_ms} = limit, fun) do
    case run(limit, fun) do
      {:error, {:throttled, wait_ms}} ->
        Process.sleep(wait_ms)
        run_wait({key, interval_ms}, fun)

      result ->
        result
    end
  end

  defp reserve(key, interval_ms, now) do
    {_, result} =
      Cachex.get_and_update(@cache, {:crm_throttle, key}, fn
        nil -> {:commit, now}
        last when last + interval_ms <= now -> {:commit, now}
        last -> {:ignore, last + interval_ms}
      end)

    case result do
      slot when is_integer(slot) and slot <= now -> :ok
      slot -> {:wait, slot}
    end
  end
end
