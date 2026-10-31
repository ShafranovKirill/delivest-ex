defmodule Delivest.Payments.Online.RefundWorker do
  use Oban.Worker,
    queue: :default,
    max_attempts: 10,
    unique: [period: :infinity, keys: [:refund_id]]

  alias Delivest.Payments.Online
  alias Delivest.Payments.Refund
  alias Delivest.Repo

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: min(trunc(:math.pow(2, attempt)) * 5, 900)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"refund_id" => id}}) do
    case Repo.get(Refund, id) |> Repo.preload(:payment) do
      %Refund{status: :pending} = refund -> Online.send_refund(refund)
      %Refund{} -> :ok
      nil -> {:cancel, :refund_not_found}
    end
  end
end
