defmodule Delivest.Logs.Buffer do
  use GenServer

  alias Delivest.Logs.Entry
  alias Delivest.Repo

  @handler_id :delivest_db_logs
  @flush_interval :timer.seconds(2)
  @batch_size 200
  @max_pending 5_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def push(entry), do: GenServer.cast(__MODULE__, {:push, entry})

  def flush, do: GenServer.call(__MODULE__, :flush)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    :ok =
      :logger.add_handler(@handler_id, Delivest.Logs.Handler, %{
        level: Keyword.fetch!(opts, :level)
      })

    schedule_flush()
    {:ok, %{entries: [], count: 0}}
  end

  @impl true
  def handle_cast({:push, _entry}, %{count: count} = state) when count >= @max_pending,
    do: {:noreply, state}

  def handle_cast({:push, entry}, state) do
    state = %{entries: [entry | state.entries], count: state.count + 1}
    {:noreply, if(state.count >= @batch_size, do: write(state), else: state)}
  end

  @impl true
  def handle_call(:flush, _from, state), do: {:reply, :ok, write(state)}

  @impl true
  def handle_info(:flush, state) do
    schedule_flush()
    {:noreply, write(state)}
  end

  @impl true
  def terminate(_reason, state) do
    :logger.remove_handler(@handler_id)
    write(state)
  end

  defp write(%{entries: []} = state), do: state

  defp write(%{entries: entries}) do
    Repo.insert_all(Entry, Enum.reverse(entries))
    %{entries: [], count: 0}
  rescue
    _error -> %{entries: [], count: 0}
  end

  defp schedule_flush, do: Process.send_after(self(), :flush, @flush_interval)
end
