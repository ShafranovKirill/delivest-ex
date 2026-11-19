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
          [{:snapshot, revisions, boundaries, epoch, checked_at}]
          when is_integer(checked_at) ->
            if System.monotonic_time(:millisecond) - checked_at <= @max_age_ms do
              global = Map.get(revisions, {section, "*"}, 0)
              local = if scope == "*", do: 0, else: Map.get(revisions, {section, scope}, 0)
              phase = temporal_phase(boundaries, section, scope, System.system_time(:millisecond))
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
          [{:snapshot, _revisions, _boundaries, _epoch, checked_at}] ->
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

  defp temporal_phase(boundaries, section, scope, now) do
    boundaries
    |> Map.get({section, scope}, [])
    |> Enum.reduce(0, fn time, latest -> if time <= now, do: max(time, latest), else: latest end)
  end

  @impl true
  def init(_state) do
    Process.flag(:trap_exit, true)
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

    state = %{
      notifier: nil,
      revisions: %{},
      epoch: nil,
      pending: false,
      boundaries: %{},
      temporal: %{},
      phases: %{}
    }

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
        state = %{state | boundaries: Map.delete(state.boundaries, key)}
        {:noreply, reconcile_boundaries(state)}

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

  defp put_boundary(state, {section, scope} = key, time) do
    delay = max(1, time - System.system_time(:millisecond))
    ref = Process.send_after(self(), {:boundary_reached, section, scope, time}, delay)
    %{state | boundaries: Map.put(state.boundaries, key, {time, ref})}
  end

  defp reconcile_boundaries(state) do
    now = System.system_time(:millisecond)

    phases =
      Map.new(state.temporal, fn {{section, scope} = key, _times} ->
        {key, temporal_phase(state.temporal, section, scope, now)}
      end)

    Enum.each(phases, fn {{section, scope} = key, phase} ->
      if Map.get(state.phases, key, 0) != phase do
        prune(section, scope)

        Phoenix.PubSub.broadcast(Delivest.PubSub, "storefront:#{scope}", %{
          section: section,
          scope: scope,
          revision: phase
        })
      end
    end)

    next =
      Map.new(state.temporal, fn {key, times} ->
        {key, times |> Enum.filter(&(&1 > now)) |> Enum.min(fn -> nil end)}
      end)
      |> Enum.reject(fn {_key, time} -> is_nil(time) end)
      |> Map.new()

    state = %{state | phases: phases}

    Enum.reduce((Map.keys(state.boundaries) ++ Map.keys(next)) |> Enum.uniq(), state, fn key,
                                                                                         acc ->
      case {Map.get(acc.boundaries, key), Map.get(next, key)} do
        {{time, _ref}, time} ->
          acc

        {{_time, ref}, nil} ->
          Process.cancel_timer(ref)
          %{acc | boundaries: Map.delete(acc.boundaries, key)}

        {{_time, ref}, time} ->
          Process.cancel_timer(ref)
          put_boundary(acc, key, time)

        {nil, nil} ->
          acc

        {nil, time} ->
          put_boundary(acc, key, time)
      end
    end)
  end

  defp refresh(state) do
    # One statement gives revisions, epoch and temporal data the same MVCC view.
    # Keep only the latest elapsed boundary per scope plus all future boundaries.
    sql = """
    WITH temporal_source AS (
      SELECT 'menu'::text AS section, branch_id::text AS scope, until AS boundary
      FROM product_stops WHERE until IS NOT NULL
      UNION ALL
      SELECT 'menu', branch_id::text, until FROM modifier_stops WHERE until IS NOT NULL
      UNION ALL
      SELECT 'menu', branch_id::text, starts_at
      FROM promotions WHERE enabled AND deleted_at IS NULL AND starts_at IS NOT NULL
      UNION ALL
      SELECT 'menu', branch_id::text, ends_at
      FROM promotions WHERE enabled AND deleted_at IS NULL AND ends_at IS NOT NULL
      UNION ALL
      SELECT 'branches', '*', NULLIF(intake->>'paused_until', '')::timestamptz AT TIME ZONE 'UTC'
      FROM branch_info i JOIN branches b ON b.id = i.branch_id
      WHERE b.is_active AND b.deleted_at IS NULL AND intake->>'paused_until' IS NOT NULL
      UNION ALL
      SELECT 'branches', '*', NULLIF(intake->>'load_until', '')::timestamptz AT TIME ZONE 'UTC'
      FROM branch_info i JOIN branches b ON b.id = i.branch_id
      WHERE b.is_active AND b.deleted_at IS NULL AND intake->>'load_until' IS NOT NULL
      UNION ALL
      SELECT 'franchise', '*', fetched_at + INTERVAL '7 days'
      FROM franchise_ratings WHERE provider = 'yandex'
    ), boundary_times AS (
      SELECT section, scope,
        (extract(epoch FROM boundary AT TIME ZONE 'UTC') * 1000)::bigint AS time
      FROM temporal_source WHERE boundary IS NOT NULL
    ), bounded AS (
      SELECT section, scope, time FROM boundary_times WHERE time > $1
      UNION ALL
      SELECT section, scope, max(time) FROM boundary_times
      WHERE time <= $1 GROUP BY section, scope
    )
    SELECT e.epoch, 'revision' AS kind, r.section, r.scope, r.revision::bigint
    FROM storefront_epoch e JOIN storefront_revisions r ON true
    UNION ALL
    SELECT e.epoch, 'boundary', b.section, b.scope, b.time
    FROM storefront_epoch e JOIN bounded b ON true
    UNION ALL
    SELECT e.epoch, 'epoch', NULL::text, NULL::text, NULL::bigint FROM storefront_epoch e
    """

    case Repo.query(sql, [System.system_time(:millisecond)]) do
      {:ok, %{rows: rows}} when rows != [] ->
        epoch = rows |> hd() |> hd()

        revisions =
          rows
          |> Enum.filter(fn [_epoch, kind | _] -> kind == "revision" end)
          |> Map.new(fn [_epoch, _kind, section, scope, revision] ->
            {{section, scope}, revision}
          end)

        temporal =
          rows
          |> Enum.filter(fn [_epoch, kind | _] -> kind == "boundary" end)
          |> Enum.group_by(
            fn [_epoch, _kind, section, scope, _time] -> {section, scope} end,
            fn [_epoch, _kind, _section, _scope, time] -> time end
          )
          |> Map.new(fn {key, times} -> {key, Enum.uniq(times)} end)

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

        :ets.insert(
          @table,
          {:snapshot, revisions, temporal, epoch, System.monotonic_time(:millisecond)}
        )

        for {{section, scope}, revision} <- changed do
          Phoenix.PubSub.broadcast(Delivest.PubSub, "storefront:#{scope}", %{
            section: section,
            scope: scope,
            revision: revision
          })
        end

        %{state | revisions: revisions, temporal: temporal, epoch: epoch}
        |> reconcile_boundaries()

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
