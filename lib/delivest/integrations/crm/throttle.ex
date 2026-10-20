defmodule Delivest.Integrations.Crm.Throttle do
  @cache :rate_limit_cache

  def run(nil, fun), do: fun.()

  def run({key, interval_ms}, fun) do
    key |> reserve(interval_ms) |> Process.sleep()
    fun.()
  end

  defp reserve(key, interval_ms) do
    now = System.monotonic_time(:millisecond)

    {_, slot} =
      Cachex.get_and_update(@cache, {:crm_throttle, key}, fn
        nil -> {:commit, now}
        last -> {:commit, max(now, last + interval_ms)}
      end)

    max(slot - now, 0)
  end
end
