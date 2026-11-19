defmodule Delivest.Storefront.Revisions do
  @moduledoc "Committed public data revisions, refreshed by PostgreSQL notifications and a bounded poll."
  use GenServer
  require Logger

  alias Delivest.Repo

  @table :storefront_revisions_snapshot
  @poll_ms 5_000
  @max_age_ms 20_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def sync, do: GenServer.call(__MODULE__, :sync, 5_000)

  def current(section, scope \\ "*") when is_binary(section) and is_binary(scope) do
    case :ets.whereis(@table) do
      :undefined ->
        {:error, :stale}

      _ ->
        case :ets.lookup(@table, :snapshot) do
          [{:snapshot, revisions, epoch, checked_at}]
          when is_integer(checked_at) ->
            if System.monotonic_time(:millisecond) - checked_at <= @max_age_ms do
              global = Map.get(revisions, {section, "*"}, 0)
              local = if scope == "*", do: 0, else: Map.get(revisions, {section, scope}, 0)
              phase = temporal_phase(section, scope)
              {:ok, "#{epoch}:#{global}:#{local}:#{phase}"}
            else
              {:error, :stale}
            end

          _ ->
            {:error, :stale}
        end
    end
  end

  def lease_remaining_ms do
    case :ets.whereis(@table) do
      :undefined ->
        0

      _ ->
        case :ets.lookup(@table, :snapshot) do
          [{:snapshot, _revisions, _epoch, checked_at}] ->
            max(0, @max_age_ms - (System.monotonic_time(:millisecond) - checked_at))

          _ ->
            0
        end
    end
  end

  def db_matches?(section, scope, expected) do
    sql = """
    SELECT e.epoch,
      COALESCE(MAX(r.revision) FILTER (WHERE r.scope = '*'), 0),
      COALESCE(MAX(r.revision) FILTER (WHERE r.scope = $2), 0)
    FROM storefront_epoch e
    LEFT JOIN storefront_revisions r ON r.section = $1 AND r.scope IN ('*', $2)
    GROUP BY e.epoch
    """

    case Repo.query(sql, [section, scope]) do
      {:ok, %{rows: [[epoch, global, local]]}} ->
        local = if scope == "*", do: 0, else: local

        String.starts_with?(expected, "#{epoch}:#{global}:#{local}:") and
          current(section, scope) == {:ok, expected}

      _ ->
        false
    end
  end

  def schedule_boundary(branch_id, %DateTime{} = boundary),
    do: schedule_boundary("menu", branch_id, boundary)

  def schedule_boundary(section, scope, %DateTime{} = boundary) do
    GenServer.cast(
      __MODULE__,
      {:boundary, section, scope, DateTime.to_unix(boundary, :millisecond)}
    )
  end

  defp temporal_phase(section, scope) do
    case :ets.lookup(@table, {:temporal, section, scope}) do
      [{{:temporal, ^section, ^scope}, phase}] -> phase
      _ -> 0
    end
  end

  @impl true
  def init(_state) do
    Process.flag(:trap_exit, true)
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    state = %{notifier: nil, revisions: %{}, epoch: nil, pending: false, boundaries: %{}}
    state = connect_notifications(state)
    rotate_epoch()
    state = refresh(state)
    Process.send_after(self(), :poll, @poll_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = state |> connect_notifications() |> refresh()
    Process.send_after(self(), :poll, @poll_ms)
    {:noreply, state}
  end

  def handle_info(
        {:notification, _pid, _ref, "storefront_revision", _payload},
        %{pending: false} = state
      ) do
    Process.send_after(self(), :refresh, 50)
    {:noreply, %{state | pending: true}}
  end

  def handle_info({:notification, _pid, _ref, "storefront_revision", _payload}, state),
    do: {:noreply, state}

  def handle_info(:refresh, state), do: {:noreply, state |> Map.put(:pending, false) |> refresh()}

  def handle_info({:EXIT, pid, reason}, %{notifier: pid} = state) do
    Logger.warning("Storefront revision listener disconnected: #{inspect(reason)}")
    Process.send_after(self(), :reconnect, 1_000)
    {:noreply, %{state | notifier: nil}}
  end

  def handle_info(:reconnect, state),
    do: {:noreply, state |> connect_notifications() |> refresh()}

  def handle_info({:boundary_reached, section, scope, time}, state) do
    key = {section, scope}

    case state.boundaries[key] do
      {^time, _ref} ->
        phase = temporal_phase(section, scope) + 1
        :ets.insert(@table, {{:temporal, section, scope}, phase})
        prune(section, scope)

        Phoenix.PubSub.broadcast(Delivest.PubSub, "storefront:#{scope}", %{
          section: section,
          scope: scope,
          revision: phase
        })

        {:noreply, %{state | boundaries: Map.delete(state.boundaries, key)}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def handle_call(:sync, _from, state) do
    state = refresh(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:boundary, section, scope, time}, state) do
    key = {section, scope}

    case state.boundaries[key] do
      {existing, _ref} when existing <= time ->
        {:noreply, state}

      {_existing, ref} ->
        Process.cancel_timer(ref)
        {:noreply, put_boundary(state, key, time)}

      nil ->
        {:noreply, put_boundary(state, key, time)}
    end
  end

  defp put_boundary(state, {section, scope} = key, time) do
    delay = max(1, time - System.system_time(:millisecond))
    ref = Process.send_after(self(), {:boundary_reached, section, scope, time}, delay)
    %{state | boundaries: Map.put(state.boundaries, key, {time, ref})}
  end

  defp refresh(state) do
    sql =
      "SELECT e.epoch, r.section, r.scope, r.revision FROM storefront_epoch e LEFT JOIN storefront_revisions r ON true"

    case Repo.query(sql, []) do
      {:ok, %{rows: rows}} when rows != [] ->
        epoch = rows |> hd() |> hd()

        revisions =
          rows
          |> Enum.reject(fn [_epoch, section | _] -> is_nil(section) end)
          |> Map.new(fn [_epoch, section, scope, revision] -> {{section, scope}, revision} end)

        changed =
          if epoch == state.epoch do
            (Map.keys(revisions) ++ Map.keys(state.revisions))
            |> Enum.uniq()
            |> Enum.filter(fn key ->
              Map.get(state.revisions, key, 0) != Map.get(revisions, key, 0)
            end)
            |> Enum.map(&{&1, Map.get(revisions, &1, 0)})
          else
            Map.to_list(revisions)
          end

        if state.epoch && epoch != state.epoch do
          Cachex.clear(:storefront_cache)

          Enum.each(
            [
              :franchise_cache,
              :branch_cache,
              :menu_cache,
              :promo_cache,
              :stock_cache,
              :stop_cache
            ],
            &Cachex.clear/1
          )

          Phoenix.PubSub.broadcast(Delivest.PubSub, "storefront:*", %{
            section: "epoch",
            scope: "*",
            revision: epoch
          })
        else
          Enum.each(changed, fn {{section, scope}, _revision} -> prune(section, scope) end)
        end

        :ets.insert(@table, {:snapshot, revisions, epoch, System.monotonic_time(:millisecond)})

        for {{section, scope}, revision} <- changed do
          Phoenix.PubSub.broadcast(Delivest.PubSub, "storefront:#{scope}", %{
            section: section,
            scope: scope,
            revision: revision
          })
        end

        %{state | revisions: revisions, epoch: epoch}

      {:error, reason} ->
        Logger.warning("Storefront revision refresh failed: #{inspect(reason)}")
        state

      _ ->
        state
    end
  end

  defp rotate_epoch do
    Repo.transaction(fn ->
      Repo.query!(
        "UPDATE storefront_epoch SET epoch = md5(random()::text || clock_timestamp()::text)",
        []
      )

      Repo.query!("SELECT pg_notify('storefront_revision', 'epoch')", [])
    end)
  rescue
    _ -> :ok
  end

  defp prune(section, scope) do
    purge_source(section, scope)

    case Cachex.keys(:storefront_cache) do
      {:ok, keys} ->
        Enum.each(keys, fn key ->
          if affected?(key, section, scope), do: Cachex.del(:storefront_cache, key)
        end)

      _ ->
        :ok
    end
  end

  defp purge_source("franchise", _scope), do: Cachex.clear(:franchise_cache)
  defp purge_source("branches", _scope), do: Cachex.clear(:branch_cache)

  defp purge_source("menu", "*") do
    Cachex.clear(:menu_cache)
    Cachex.clear(:promo_cache)
    Cachex.clear(:stop_cache)
  end

  defp purge_source("menu", scope) do
    purge_branch_keys(:menu_cache, scope)
    purge_branch_keys(:promo_cache, scope)
    Cachex.del(:stop_cache, scope)
  end

  defp purge_source("stories", "*"), do: Cachex.clear(:stock_cache)
  defp purge_source("stories", scope), do: Cachex.del(:stock_cache, scope)
  defp purge_source(_, _), do: :ok

  defp purge_branch_keys(cache, branch_id) do
    case Cachex.keys(cache) do
      {:ok, keys} ->
        Enum.each(keys, fn
          {_, ^branch_id, _} = key -> Cachex.del(cache, key)
          _ -> :ok
        end)

      _ ->
        :ok
    end
  end

  defp affected?({:franchise, _}, "franchise", _), do: true
  defp affected?({:branches, _}, "branches", _), do: true

  defp affected?({:menu, branch_id, _locale, _}, "menu", scope),
    do: scope == "*" or branch_id == scope

  defp affected?({:stories, branch_id, _}, "stories", scope),
    do: scope == "*" or branch_id == scope

  defp affected?({:advertising, branch_id, _}, "advertising", scope),
    do: scope == "*" or branch_id == scope

  defp affected?(_, _, _), do: false

  defp connect_notifications(%{notifier: pid} = state) when is_pid(pid), do: state

  defp connect_notifications(state) do
    opts = Repo.config() |> Keyword.drop([:adapter, :pool_size, :telemetry_prefix, :name])

    with {:ok, notifier} <- Postgrex.Notifications.start_link(opts),
         {:ok, _ref} <- Postgrex.Notifications.listen(notifier, "storefront_revision") do
      %{state | notifier: notifier}
    else
      error ->
        Logger.warning("Storefront revision notifications unavailable: #{inspect(error)}")
        state
    end
  end
end
