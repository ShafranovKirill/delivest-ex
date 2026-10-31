defmodule Delivest.Integrations.YandexEda.StopList do
  require Logger

  alias Delivest.Integrations.Crm.StopSync
  alias Delivest.Integrations.YandexEda.Menu
  alias Delivest.Net.Stops

  @min_timeout 2_000
  @fresh_seconds 30

  def availability(branch, settings) do
    %{
      items:
        branch
        |> Menu.product_ids(settings)
        |> unavailable_in(Stops.stopped_ids(branch.id))
        |> Enum.map(&%{itemId: &1, stock: 0}),
      modifiers:
        branch
        |> Menu.modifier_ids(settings)
        |> unavailable_in(Delivest.Net.Modifiers.stopped_ids(branch.id))
        |> Enum.map(&%{modifierId: &1, stock: 0})
    }
  end

  def refresh(branch_id) do
    if fresh?(branch_id), do: :ok, else: sync(branch_id)
  end

  defp fresh?(branch_id) do
    case StopSync.last(branch_id) do
      %{synced_at: synced_at} -> DateTime.diff(DateTime.utc_now(), synced_at) < @fresh_seconds
      _none -> false
    end
  end

  defp sync(branch_id) do
    task =
      Task.Supervisor.async_nolink(Delivest.TaskSupervisor, fn -> StopSync.sync(branch_id) end)

    case Task.yield(task, timeout(branch_id)) || Task.shutdown(task) do
      {:ok, result} ->
        result

      {:exit, reason} ->
        Logger.error("yandex eda stop list refresh crashed: #{inspect(reason)}")
        {:error, :crashed}

      _timeout ->
        Logger.warning("yandex eda stop list was not refreshed before the order")
        {:error, :timeout}
    end
  end

  defp timeout(branch_id), do: max(@min_timeout, StopSync.interval_ms(branch_id) + 1_000)

  def unavailable(branch_id, product_ids),
    do: unavailable_in(product_ids, Stops.stopped_ids(branch_id))

  defp unavailable_in(product_ids, stopped),
    do: Enum.filter(product_ids, &MapSet.member?(stopped, &1))
end
