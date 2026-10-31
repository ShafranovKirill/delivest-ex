defmodule Delivest.Integrations.Inbox.Worker do
  use Oban.Worker,
    queue: :default,
    max_attempts: 8,
    unique: [period: :infinity, keys: [:id]]

  require Logger

  alias Delivest.Integrations.{Inbox, Journal}
  alias Delivest.Integrations.Inbox.Message
  alias Delivest.Repo

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: min(trunc(:math.pow(2, attempt)) * 5, 600)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id}} = job) do
    with %Message{status: :pending} = message <- Repo.get(Message, id),
         {:ok, handler} <- Inbox.handler(message.provider) do
      [branch_id: message.branch_id]
      |> Journal.scope(fn -> handler.handle_inbox(message) end)
      |> result(message, job)
    else
      nil -> {:cancel, :message_not_found}
      %Message{} -> :ok
      {:error, reason} -> {:cancel, reason}
    end
  end

  defp result(:ok, message, job), do: result({:ok, nil}, message, job)

  defp result({:ok, _value}, message, _job) do
    Inbox.processed(message)
    :ok
  end

  defp result({:cancel, reason} = cancel, message, _job) do
    Inbox.failed(message, reason)
    cancel
  end

  defp result({:error, reason} = error, message, %Oban.Job{attempt: attempt} = job)
       when attempt >= job.max_attempts do
    Logger.error("inbox #{message.provider} #{message.event_id} failed: #{inspect(reason)}")
    Inbox.failed(message, reason)
    error
  end

  defp result({:error, reason} = error, message, _job) do
    Inbox.retrying(message, reason)
    error
  end
end
