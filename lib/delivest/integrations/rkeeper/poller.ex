defmodule Delivest.Integrations.Rkeeper.Poller do
  @behaviour Delivest.Integrations.Poller

  alias Delivest.Integrations.Rkeeper
  alias Delivest.Integrations.Rkeeper.PollWorker

  @batch_size 100
  @first_id "00000000-0000-0000-0000-000000000000"

  @impl true
  def key, do: :rkeeper

  @impl true
  def interval, do: 30

  @impl true
  def targets, do: Rkeeper.active_branches()

  @impl true
  def poll(branch_id) do
    if enqueue_batch(branch_id, @first_id) > 0, do: :more, else: :done
  end

  defp enqueue_batch(branch_id, after_id) do
    case Rkeeper.active_order_ids(branch_id, after_id, @batch_size) do
      [] ->
        0

      ids ->
        Enum.each(ids, fn id ->
          {:ok, _job} = %{order_id: id} |> PollWorker.new() |> Oban.insert()
        end)

        if length(ids) == @batch_size do
          length(ids) + enqueue_batch(branch_id, List.last(ids))
        else
          length(ids)
        end
    end
  end
end
