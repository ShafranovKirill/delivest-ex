defmodule Delivest.Events.RecoveryProbe do
  @behaviour Delivest.Events.Subscriber

  alias Delivest.Events.Event
  alias Delivest.Repo

  def key, do: :recovery_probe
  def events, do: ["order.status_changed"]

  def handle(event) do
    Repo.insert!(%Event{
      type: "probe.side_effect",
      aggregate_type: event.aggregate_type,
      aggregate_id: event.aggregate_id,
      payload: %{},
      actor: %{}
    })

    case Application.get_env(:delivest, __MODULE__) do
      %{owner: owner, barrier: :before_commit} ->
        backend = Ecto.Adapters.SQL.query!(Repo, "SELECT pg_backend_pid()", []).rows
        send(owner, {:probe_written, self(), event.id, backend})

        receive do
          {:continue, id} when id == event.id -> :ok
        end

      _ ->
        :ok
    end
  end
end
