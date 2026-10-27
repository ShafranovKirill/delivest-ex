defmodule Delivest.Integrations.YandexEda.StopList do
  alias Delivest.Integrations.Crm.StopSync
  alias Delivest.Integrations.YandexEda.Menu
  alias Delivest.Net.Stops

  @fresh_timeout 2_000

  def availability(branch, settings) do
    %{
      items:
        branch
        |> Menu.product_ids(settings)
        |> unavailable_in(Stops.stopped_ids(branch.id))
        |> Enum.map(&%{itemId: &1, stock: 0}),
      modifiers: []
    }
  end

  def refresh(branch_id) do
    task = Task.async(fn -> StopSync.sync(branch_id) end)

    case Task.yield(task, @fresh_timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      _timeout -> {:error, :timeout}
    end
  end

  def unavailable(branch_id, product_ids),
    do: unavailable_in(product_ids, Stops.stopped_ids(branch_id))

  defp unavailable_in(product_ids, stopped),
    do: Enum.filter(product_ids, &MapSet.member?(stopped, &1))
end
