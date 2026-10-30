defmodule Delivest.Fiscal.PollWorker do
  use Oban.Worker, queue: :fiscal, max_attempts: 10

  alias Delivest.Fiscal
  alias Delivest.Fiscal.Receipt

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"receipt_id" => id}}) do
    case Fiscal.get(id) do
      %Receipt{status: :wait} = receipt -> poll(receipt)
      _ -> :ok
    end
  end

  defp poll(receipt) do
    case Fiscal.poll(receipt) do
      {:ok, %Receipt{status: :wait}} -> {:error, :still_waiting}
      {:ok, _receipt} -> :ok
      error -> error
    end
  end
end
