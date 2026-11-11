defmodule Delivest.MaintenanceTestWorker do
  def perform(_job) do
    case Application.get_env(:delivest, __MODULE__, :ok) do
      {:notify, pid} ->
        send(pid, :maintenance_called)
        :ok

      result ->
        result
    end
  end
end
