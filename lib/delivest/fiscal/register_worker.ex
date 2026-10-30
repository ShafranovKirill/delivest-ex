defmodule Delivest.Fiscal.RegisterWorker do
  use Oban.Worker, queue: :fiscal, max_attempts: 8, unique: [period: 300, fields: [:args]]

  require Logger

  alias Delivest.Fiscal
  alias Delivest.Fiscal.Receipt

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: min(attempt * attempt * 15, 1800)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"receipt_id" => id}, attempt: attempt, max_attempts: max}) do
    case Fiscal.get(id) do
      %Receipt{status: :pending} = receipt ->
        receipt |> Fiscal.register() |> handle(receipt, attempt, max)

      _ ->
        :ok
    end
  end

  defp handle({:ok, _receipt}, _receipt_before, _attempt, _max), do: :ok

  defp handle({:error, reason} = error, receipt, attempt, max) do
    message = inspect(reason)
    Logger.error("fiscal receipt #{receipt.id} attempt #{attempt}/#{max} failed: #{message}")

    case Fiscal.classify_error(receipt, reason) do
      {:snooze, seconds} ->
        Fiscal.attempted(receipt, message, attempt)
        {:snooze, seconds}

      :retry when attempt < max ->
        Fiscal.attempted(receipt, message, attempt)
        error

      _final ->
        Fiscal.failed(receipt, message, attempt)
        {:cancel, reason}
    end
  end
end
