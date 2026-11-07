defmodule Delivest.Integrations.YandexEda.StopList do
  require Logger

  alias Delivest.Integrations.Crm.StopSync
  alias Delivest.Integrations.YandexEda.Menu
  alias Delivest.Net.Stops

  @refresh_budget_ms 2_000
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

    case Task.yield(task, @refresh_budget_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        if match?({:error, _}, result), do: degraded(branch_id, result)
        result

      {:exit, _reason} ->
        degraded(branch_id, :crashed)
        {:error, :crashed}

      _timeout ->
        degraded(branch_id, :timeout)
        {:error, :timeout}
    end
  end

  defp degraded(branch_id, reason) do
    age =
      case StopSync.last(branch_id) do
        %{synced_at: synced_at} -> DateTime.diff(DateTime.utc_now(), synced_at, :second)
        _ -> -1
      end

    reason = degradation_reason(reason)

    :telemetry.execute(
      [:delivest, :yandex_eda, :stop_list, :degraded],
      %{count: 1, snapshot_age_seconds: age},
      %{branch_id: branch_id, reason: reason}
    )

    Logger.warning(
      "yandex eda stop list refresh degraded for branch #{branch_id}; " <>
        "snapshot_age_seconds=#{age}; reason=#{reason}; using local stops"
    )
  end

  defp degradation_reason({:error, {:http_error, status, _body}}), do: "http_#{status}"
  defp degradation_reason({:error, _reason}), do: "provider_error"
  defp degradation_reason(reason), do: reason

  def unavailable(branch_id, product_ids),
    do: unavailable_in(product_ids, Stops.stopped_ids(branch_id))

  defp unavailable_in(product_ids, stopped),
    do: Enum.filter(product_ids, &MapSet.member?(stopped, &1))
end
