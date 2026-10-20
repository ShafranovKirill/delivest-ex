defmodule Delivest.Audit do
  require Logger

  alias Delivest.Audit.{Actor, Event, Failure, Recorder}

  def subscribe, do: Phoenix.PubSub.subscribe(Delivest.PubSub, Recorder.topic())

  def list_events(params \\ %{}), do: Flop.validate_and_run(Event, params, for: Event)

  def record(actor, action, subject, opts \\ []),
    do: Recorder.record(actor, action, subject, opts)

  def track(result, actor, action, opts \\ [])

  def track({:ok, subject} = result, actor, action, opts) do
    Recorder.record(actor, action, subject, opts)
    result
  end

  def track(error, actor, action, _opts) do
    by = actor |> Actor.describe() |> Actor.label()
    Logger.warning("#{action} failed by #{by}: #{Failure.reason(error)}")
    error
  end
end
