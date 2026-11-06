defmodule Delivest.InstanceBackup.Maintenance do
  @moduledoc "Quiesces the local application for external restores and holds unsafe boots."
  use GenServer

  alias Delivest.InstanceBackup

  @poll_ms 1_000

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

  def hold_boot?(dir \\ InstanceBackup.dir()) do
    if is_binary(dir) and dir != "" do
      active_path = Path.join(dir, "active.json")

      if File.lstat(active_path) != {:error, :enoent} do
        with %{"id" => id} <- InstanceBackup.read_json(active_path),
             true <- InstanceBackup.valid_id?(id),
             %{"mode" => mode} when mode in ["compose", "external"] <-
               InstanceBackup.read_json(Path.join([dir, "jobs", id, "request.json"])),
             %{"phase" => phase, "safe_to_resume" => safe} <-
               InstanceBackup.read_json(Path.join([dir, "jobs", id, "status.json"])),
             true <- phase in ~w(queued waiting running complete failed interrupted),
             true <- is_boolean(safe) do
          safe == false or (mode == "external" and phase in ~w(queued waiting running))
        else
          _ -> true
        end
      else
        false
      end
    else
      false
    end
  end

  @impl true
  def init(opts) do
    dir = Keyword.get(opts, :dir, InstanceBackup.dir())
    job = InstanceBackup.active(dir)

    recovered_hold =
      not is_nil(job) and File.exists?(Path.join([dir, "jobs", job.id, "quiesced.json"]))

    state = %{
      supervisor: Keyword.fetch!(opts, :supervisor),
      children: Keyword.fetch!(opts, :children),
      dir: dir,
      held: Keyword.get(opts, :held, false) or recovered_hold,
      marker: nil
    }

    schedule()
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = reconcile(state, InstanceBackup.active(state.dir))
    schedule()
    {:noreply, state}
  end

  defp reconcile(state, job) do
    cond do
      ((state.held and job) && InstanceBackup.terminal?(job)) and InstanceBackup.safe?(job) ->
        resume(state)

      state.held ->
        ensure_marker(state, job)

      job && job.request["mode"] == "external" &&
          job.status["phase"] in ~w(queued waiting running) ->
        quiesce(state, job.id)

      true ->
        state
    end
  end

  defp quiesce(state, id) do
    # The authoritative startup order keeps Repo first and Endpoint last.
    Enum.each(Enum.reverse(state.children), fn spec ->
      :ok = Supervisor.terminate_child(state.supervisor, spec.id)
    end)

    marker = Path.join([state.dir, "jobs", id, "quiesced.json"])
    :ok = InstanceBackup.write_json(marker, %{id: id})
    %{state | held: true, marker: marker}
  end

  defp ensure_marker(state, %{id: id, request: %{"mode" => "external"}}) do
    marker = Path.join([state.dir, "jobs", id, "quiesced.json"])

    stopped? =
      Enum.all?(Supervisor.which_children(state.supervisor), fn
        {Delivest.InstanceBackup.Maintenance, _, _, _} -> true
        {_, :undefined, _, _} -> true
        _ -> false
      end)

    if stopped? and not File.exists?(marker),
      do: :ok = InstanceBackup.write_json(marker, %{id: id})

    state
  end

  defp ensure_marker(state, _job), do: state

  defp resume(state) do
    Enum.each(state.children, fn spec ->
      case Supervisor.restart_child(state.supervisor, spec.id) do
        {:error, :not_found} -> {:ok, _} = Supervisor.start_child(state.supervisor, spec)
        {:error, :running} -> :ok
        {:ok, _} -> :ok
        {:ok, _, _} -> :ok
      end
    end)

    %{state | held: false, marker: nil}
  end

  defp schedule, do: Process.send_after(self(), :poll, @poll_ms)
end
