defmodule Delivest.Audit do
  require Logger

  import Ecto.Query

  alias Delivest.Audit.{Actor, Event, Failure, Recorder}
  alias Delivest.Identity.Branch
  alias Delivest.Repo

  def subscribe, do: Phoenix.PubSub.subscribe(Delivest.PubSub, Recorder.topic())

  def list_events(params \\ %{}) do
    Event
    |> join(:left, [e], b in Branch, on: b.id == e.branch_id, as: :branch)
    |> Flop.validate_and_run(params, for: Event)
  end

  def list_staff_actors do
    Event
    |> where([e], e.actor_type == :staff and not is_nil(e.actor_id))
    |> distinct(true)
    |> select([e], {e.actor_id, e.actor_name})
    |> Repo.all()
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.sort_by(&elem(&1, 1))
  end

  def list_actions do
    Event
    |> distinct(true)
    |> select([e], e.action)
    |> order_by([e], asc: e.action)
    |> Repo.all()
  end

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
