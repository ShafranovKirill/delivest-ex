defmodule Delivest.Segments.Refresh do
  @moduledoc "One shared daily refresh. Order history is read once per changed client and branch."
  import Ecto.Query
  require Logger

  alias Delivest.{Background, Features, Repo}
  alias Delivest.Identity.{Branch, Client}
  alias Delivest.Oms.Order
  alias Delivest.Segments.{Rules, Segment}

  @batch 250
  @zero "00000000-0000-0000-0000-000000000000"

  def perform(:franchise, context) do
    with :ok <- Background.checkpoint(context) do
      refresh(context)
    end
  rescue
    error ->
      Logger.error(Exception.format(:error, error, __STACKTRACE__))
      {:error, :refresh_failed}
  end

  def perform(_, _), do: {:error, :invalid_scope}

  defp refresh(context) do
    groups = Repo.all(from s in Segment, where: s.kind == :dynamic, preload: [:branches])

    if groups == [] do
      :ok
    else
      with :ok <- cleanup_orphans(context) do
        branches = enabled_branches()
        used_ids = groups |> Enum.flat_map(&branch_ids(&1, branches)) |> Enum.uniq()

        if used_ids == [] do
          :ok
        else
          with {:ok, states} <- calculate_branches(used_ids, context),
               {:ok, publications} <- calculate_groups(groups, branches, states, context),
               :ok <- publish(states, publications, context) do
            acknowledge_dirty(states, context)
            cleanup_orphans(context)
            :ok
          end
        end
      end
    end
  end

  defp enabled_branches do
    Repo.all(from b in Branch, where: is_nil(b.deleted_at), select: b.id)
    |> Enum.filter(&Features.enabled?("segments", {:branch, &1}))
  end

  defp branch_ids(%Segment{scope: :franchise}, enabled), do: enabled

  defp branch_ids(%Segment{scope: :branches, branches: branches}, enabled) do
    ids = Enum.map(branches, & &1.id)
    if ids != [] and Enum.all?(ids, &(&1 in enabled)), do: ids, else: []
  end

  defp calculate_branches(ids, context) do
    Enum.reduce_while(ids, {:ok, %{}}, fn branch_id, {:ok, acc} ->
      with :ok <- Background.checkpoint(context),
           {:ok, token} <- Features.snapshot("segments", {:branch, branch_id}),
           {:ok, state} <- calculate_branch(branch_id, token, context) do
        {:cont, {:ok, Map.put(acc, branch_id, state)}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp calculate_branch(branch_id, token, context) do
    old =
      Repo.query!(
        "SELECT snapshot_id, feature_generation, parent_generation FROM segment_metric_states WHERE branch_id=$1",
        [Ecto.UUID.dump!(branch_id)]
      ).rows

    {old_snapshot, old_generation, old_parent} =
      case old do
        [[snapshot, generation, parent]] -> {Ecto.UUID.load!(snapshot), generation, parent}
        _ -> {nil, nil, nil}
      end

    snapshot = Ecto.UUID.generate()

    baseline? =
      old_snapshot == nil or old_generation != token.branch or old_parent != token.franchise

    if baseline? do
      walk_clients(
        @zero,
        fn clients ->
          pending = dirty_versions(branch_id, clients)

          with :ok <- write_metrics(branch_id, snapshot, clients) do
            stage_ack(snapshot, branch_id, pending)
            :ok
          end
        end,
        context
      )
    else
      copy_metrics(old_snapshot, snapshot, branch_id, @zero, context)
      |> case do
        :ok -> process_dirty(branch_id, snapshot, @zero, context)
        error -> error
      end
    end
    |> case do
      :ok -> {:ok, %{snapshot: snapshot, token: token, baseline?: baseline?}}
      error -> error
    end
  end

  defp walk_clients(after_id, fun, context) do
    with :ok <- Background.checkpoint(context) do
      clients =
        Repo.all(
          from c in Client,
            where: c.id > ^after_id and c.status == :active and is_nil(c.deleted_at),
            order_by: [asc: c.id],
            limit: @batch,
            select: c.id
        )

      case clients do
        [] ->
          :ok

        ids ->
          with :ok <- fun.(ids) do
            walk_clients(List.last(ids), fun, context)
          end
      end
    end
  end

  defp copy_metrics(old, fresh, branch_id, after_id, context) do
    with :ok <- Background.checkpoint(context) do
      query = """
      INSERT INTO segment_customer_metrics(snapshot_id, branch_id, client_id, order_count, total_spent, last_order_at)
      SELECT $1, branch_id, client_id, order_count, total_spent, last_order_at
      FROM segment_customer_metrics WHERE snapshot_id=$2 AND branch_id=$3 AND client_id>$4
      ORDER BY client_id LIMIT #{@batch} RETURNING client_id
      """

      rows =
        Repo.query!(query, Enum.map([fresh, old, branch_id, after_id], &Ecto.UUID.dump!/1)).rows

      case rows do
        [] ->
          :ok

        _ ->
          copy_metrics(old, fresh, branch_id, Ecto.UUID.load!(List.last(rows) |> hd()), context)
      end
    end
  end

  defp process_dirty(branch_id, snapshot, after_id, context) do
    with :ok <- Background.checkpoint(context) do
      rows =
        Repo.query!(
          "SELECT client_id, revision FROM segment_dirty_clients WHERE branch_id=$1 AND client_id>$2 ORDER BY client_id LIMIT #{@batch}",
          [Ecto.UUID.dump!(branch_id), Ecto.UUID.dump!(after_id)]
        ).rows

      case rows do
        [] ->
          :ok

        _ ->
          ids = Enum.map(rows, fn [id, _] -> Ecto.UUID.load!(id) end)

          Repo.delete_all(
            from m in "segment_customer_metrics",
              where:
                m.snapshot_id == type(^snapshot, :binary_id) and
                  m.branch_id == type(^branch_id, :binary_id) and
                  m.client_id in ^Enum.map(ids, &Ecto.UUID.dump!/1)
          )

          :ok = write_metrics(branch_id, snapshot, ids)

          stage_ack(snapshot, branch_id, rows)

          process_dirty(branch_id, snapshot, List.last(ids), context)
      end
    end
  end

  defp write_metrics(branch_id, snapshot, ids) do
    metrics =
      Repo.all(
        from o in Order,
          where:
            o.client_id in ^ids and o.branch_id == ^branch_id and
              is_nil(o.deleted_at),
          group_by: o.client_id,
          select:
            {o.client_id, fragment("COUNT(?) FILTER (WHERE ? = 'completed')", o.id, o.status),
             fragment(
               "COALESCE(SUM(GREATEST(0, ? - COALESCE((SELECT SUM(r.amount) FROM order_refunds r WHERE r.order_id = ? AND r.status = 'succeeded'), 0))) FILTER (WHERE ? = 'completed'), 0)",
               o.total_amount,
               o.id,
               o.status
             ), fragment("MAX(?) FILTER (WHERE ? = 'completed')", o.inserted_at, o.status)}
      )

    if metrics != [] do
      Repo.insert_all(
        "segment_customer_metrics",
        Enum.map(metrics, fn {id, count, total, last} ->
          %{
            snapshot_id: Ecto.UUID.dump!(snapshot),
            branch_id: Ecto.UUID.dump!(branch_id),
            client_id: Ecto.UUID.dump!(id),
            order_count: count,
            total_spent: money_integer(total),
            last_order_at: naive(last)
          }
        end),
        on_conflict: :nothing
      )
    end

    :ok
  end

  defp dirty_versions(branch_id, ids) do
    Repo.query!(
      "SELECT client_id, revision FROM segment_dirty_clients WHERE branch_id=$1 AND client_id = ANY($2::uuid[])",
      [Ecto.UUID.dump!(branch_id), Enum.map(ids, &Ecto.UUID.dump!/1)]
    ).rows
  end

  defp stage_ack(_snapshot, _branch_id, []), do: :ok

  defp stage_ack(snapshot, branch_id, rows) do
    Repo.insert_all(
      "segment_dirty_ack",
      Enum.map(rows, fn [id, rev] ->
        %{
          snapshot_id: Ecto.UUID.dump!(snapshot),
          branch_id: Ecto.UUID.dump!(branch_id),
          client_id: id,
          revision: rev
        }
      end),
      on_conflict: :nothing
    )

    :ok
  end

  defp calculate_groups(groups, enabled, states, context) do
    Enum.reduce_while(groups, {:ok, []}, fn group, {:ok, acc} ->
      ids = branch_ids(group, enabled)

      if ids == [] do
        {:cont, {:ok, acc}}
      else
        snapshot = Ecto.UUID.generate()

        case walk_clients(
               @zero,
               fn clients -> evaluate_batch(group, ids, states, snapshot, clients) end,
               context
             ) do
          :ok -> {:cont, {:ok, [{group.id, group.revision, snapshot} | acc]}}
          error -> {:halt, error}
        end
      end
    end)
  end

  defp evaluate_batch(group, ids, states, snapshot, clients) do
    snapshots = Enum.map(ids, &states[&1].snapshot)

    metrics =
      Repo.all(
        from m in "segment_customer_metrics",
          where:
            m.snapshot_id in ^Enum.map(snapshots, &Ecto.UUID.dump!/1) and
              m.client_id in ^Enum.map(clients, &Ecto.UUID.dump!/1),
          select: {m.client_id, m.order_count, m.total_spent, m.last_order_at}
      )
      |> Enum.group_by(fn {id, _, _, _} -> Ecto.UUID.load!(id) end)

    clients =
      if group.scope == :branches,
        do: Enum.filter(clients, &Map.has_key?(metrics, &1)),
        else: clients

    now = DateTime.utc_now()

    matches =
      Enum.filter(clients, fn client_id ->
        values = Map.get(metrics, client_id, [])

        aggregate =
          Enum.reduce(values, %{order_count: 0, total_spent: 0, last_order_at: nil}, fn {_, count,
                                                                                         total,
                                                                                         last},
                                                                                        acc ->
            %{
              order_count: acc.order_count + count,
              total_spent: acc.total_spent + total,
              last_order_at: max_datetime(acc.last_order_at, utc(last))
            }
          end)

        Rules.match?(group.rules, aggregate, now)
      end)

    if matches != [] do
      Repo.insert_all(
        "segment_dynamic_members",
        Enum.map(matches, fn id ->
          %{
            segment_id: Ecto.UUID.dump!(group.id),
            snapshot_id: Ecto.UUID.dump!(snapshot),
            client_id: Ecto.UUID.dump!(id)
          }
        end),
        on_conflict: :nothing
      )
    end

    :ok
  end

  defp max_datetime(nil, at), do: at
  defp max_datetime(at, nil), do: at
  defp max_datetime(a, b), do: if(DateTime.compare(a, b) == :lt, do: b, else: a)

  defp publish(states, groups, context) do
    case Background.publish(context, fn ->
           Enum.each(states, fn {branch_id, state} ->
             if not Features.still_enabled?("segments", {:branch, branch_id}, state.token),
               do: Repo.rollback(:disabled)

             Repo.query!(
               """
               INSERT INTO segment_metric_states(branch_id, snapshot_id, feature_generation, parent_generation, last_refreshed_at)
               VALUES ($1,$2,$3,$4,$5)
               ON CONFLICT (branch_id) DO UPDATE SET snapshot_id=EXCLUDED.snapshot_id,
                 feature_generation=EXCLUDED.feature_generation,
                 parent_generation=EXCLUDED.parent_generation,
                 last_refreshed_at=EXCLUDED.last_refreshed_at
               """,
               [
                 Ecto.UUID.dump!(branch_id),
                 Ecto.UUID.dump!(state.snapshot),
                 state.token.branch,
                 state.token.franchise,
                 NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
               ]
             )
           end)

           Enum.each(groups, fn {id, revision, snapshot} ->
             {updated, _} =
               Repo.update_all(from(s in Segment, where: s.id == ^id and s.revision == ^revision),
                 set: [
                   published_snapshot_id: snapshot,
                   last_refreshed_at: DateTime.utc_now() |> DateTime.truncate(:second),
                   last_refresh_error: nil
                 ]
               )

             if updated != 1, do: Repo.rollback(:stale_segment)
           end)
         end) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp cleanup_orphans(context) do
    result =
      Enum.reduce_while(
        [
          {"segment_customer_metrics", "segment_metric_states"},
          {"segment_dynamic_members", "segments"}
        ],
        :ok,
        fn {table, owner}, :ok ->
          owner_column = if owner == "segments", do: "published_snapshot_id", else: "snapshot_id"

          query =
            "DELETE FROM #{table} WHERE ctid IN (SELECT ctid FROM #{table} WHERE snapshot_id NOT IN (SELECT #{owner_column} FROM #{owner} WHERE #{owner_column} IS NOT NULL) AND snapshot_id NOT IN (SELECT snapshot_id FROM segment_snapshot_leases) LIMIT #{@batch})"

          case cleanup_batches(query, context) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end
      )

    with :ok <- result do
      cleanup_batches(
        "DELETE FROM segment_dirty_ack WHERE ctid IN (SELECT ctid FROM segment_dirty_ack WHERE snapshot_id NOT IN (SELECT snapshot_id FROM segment_metric_states WHERE snapshot_id IS NOT NULL) LIMIT #{@batch})",
        context
      )
    end
  end

  defp acknowledge_dirty(states, context) do
    Enum.each(states, fn {_branch_id, %{snapshot: snapshot}} ->
      encoded = Ecto.UUID.dump!(snapshot)

      ack_sql = """
      WITH batch AS (SELECT ctid, branch_id, client_id, revision FROM segment_dirty_ack
        WHERE snapshot_id=$1 LIMIT #{@batch}),
      acknowledged AS (DELETE FROM segment_dirty_clients d USING batch b
        WHERE d.branch_id=b.branch_id AND d.client_id=b.client_id AND d.revision=b.revision)
      DELETE FROM segment_dirty_ack a USING batch b WHERE a.ctid=b.ctid
      """

      acknowledge_batches(ack_sql, encoded, context)
    end)
  end

  defp acknowledge_batches(ack_sql, snapshot, context) do
    with :ok <- Background.checkpoint(context),
         {:ok, count} <-
           Background.publish(context, fn -> Repo.query!(ack_sql, [snapshot]).num_rows end) do
      if count == 0, do: :ok, else: acknowledge_batches(ack_sql, snapshot, context)
    end
  end

  defp utc(nil), do: nil
  defp utc(%DateTime{} = at), do: at
  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")

  defp naive(nil), do: nil
  defp naive(%DateTime{} = at), do: DateTime.to_naive(at)
  defp naive(%NaiveDateTime{} = at), do: at

  defp money_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp money_integer(value) when is_integer(value), do: value

  defp cleanup_batches(query, context) do
    with :ok <- Background.checkpoint(context),
         {:ok, count} <- Background.publish(context, fn -> Repo.query!(query, []).num_rows end) do
      if count == 0, do: :ok, else: cleanup_batches(query, context)
    end
  end
end
