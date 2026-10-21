defmodule Delivest.Audit.Recorder do
  require Logger

  alias Delivest.Audit.{Actor, Event, Subject}
  alias Delivest.Repo

  @topic "audit_events"

  def topic, do: @topic

  def record(actor, action, subject, opts) do
    event =
      actor
      |> Actor.describe()
      |> Map.merge(Subject.describe(subject))
      |> Map.merge(%{action: action, metadata: Map.new(Keyword.get(opts, :metadata, %{}))})
      |> put_branch(Keyword.get(opts, :branch_id))

    event = Repo.insert!(struct(Event, event))

    Logger.info(
      "audit #{action} #{event.subject_type}:#{event.subject_label} by #{Actor.label(event)}"
    )

    Phoenix.PubSub.broadcast(Delivest.PubSub, @topic, {:audit_event, event})
    {:ok, event}
  rescue
    error ->
      Logger.error("audit #{action} not recorded: #{Exception.message(error)}")
      {:error, error}
  end

  defp put_branch(event, nil), do: event
  defp put_branch(event, branch_id), do: %{event | branch_id: branch_id}
end
