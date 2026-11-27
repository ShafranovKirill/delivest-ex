defmodule Delivest.Fiscal.RefundWorker do
  use Oban.Worker,
    queue: :fiscal,
    max_attempts: 10,
    unique: [period: :infinity, keys: [:refund_id]]

  alias Delivest.Fiscal

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: min(attempt * attempt * 15, 1_800)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"refund_id" => id}}) do
    case Fiscal.issue_online_refund(id) do
      {:ok, _receipt} -> :ok
      {:error, reason} when reason in [:sale_receipt_pending, :disabled] -> {:snooze, 300}
      {:error, _reason} = error -> error
    end
  end
end
