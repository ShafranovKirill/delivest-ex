defmodule Delivest.Marketing.Preview do
  @moduledoc "Bounded audience previews through the shared Background runner."
  import Ecto.Query
  alias Delivest.{Background, Marketing, Repo, Segments}
  alias Delivest.Marketing.Policy
  alias Delivest.Segments.Segment

  @page 50
  @zero "00000000-0000-0000-0000-000000000000"

  def perform(:franchise, context) do
    with :ok <- Background.checkpoint(context) do
      case next_preview() do
        nil -> cleanup_or_done(context)
        row -> process_page(row, context)
      end
    end
  end

  def perform(_, _), do: {:error, :invalid_scope}

  defp next_preview do
    Repo.query!("""
    SELECT policy_id, request_id, policy_revision, segment_revision, feature_generation, segment_snapshot_id,
      cursor_client_id, eligible_count
    FROM marketing_previews WHERE status='pending'
    ORDER BY requested_at, policy_id LIMIT 1
    """).rows
    |> List.first()
  end

  defp process_page(
         [
           policy_raw,
           request_raw,
           revision,
           segment_revision,
           feature_generation,
           snapshot_raw,
           cursor_raw,
           count
         ],
         context
       ) do
    policy_id = Ecto.UUID.load!(policy_raw)
    policy = Repo.get(Policy, policy_id)
    segment = policy && Repo.get(Segment, policy.segment_id)

    cond do
      is_nil(policy) or is_nil(segment) ->
        {:error, :missing_policy_or_segment}

      policy.revision != revision or segment.revision != segment_revision or
          context.generation.franchise != feature_generation ->
        stale(
          policy_id,
          request_raw,
          revision,
          segment_revision,
          feature_generation,
          snapshot_raw,
          context
        )

      true ->
        snapshot = if snapshot_raw, do: Ecto.UUID.load!(snapshot_raw), else: nil
        cursor = if cursor_raw, do: Ecto.UUID.load!(cursor_raw), else: @zero
        ids = Segments.published_member_page(segment, cursor, @page, snapshot)
        now = DateTime.utc_now(:second)
        eligible_cycles = Marketing.candidate_state(policy, ids, now).eligible_cycles
        next_count = count + length(eligible_cycles)

        case Background.publish(context, fn ->
               latest = Repo.get(Policy, policy_id)

               latest_segment =
                 latest &&
                   Repo.one(
                     from s in Segment, where: s.id == ^latest.segment_id, lock: "FOR SHARE"
                   )

               if latest == nil or latest_segment == nil or latest.revision != revision or
                    latest_segment.revision != segment_revision,
                  do: Repo.rollback(:stale)

               done = length(ids) < @page

               if policy.initial_mode == :future_only and eligible_cycles != [] do
                 Repo.insert_all(
                   "marketing_baseline_members",
                   Enum.map(eligible_cycles, fn {id, cycle_id} ->
                     %{
                       policy_id: policy_raw,
                       request_id: request_raw,
                       client_id: Ecto.UUID.dump!(id),
                       cycle_order_id: Ecto.UUID.dump!(cycle_id)
                     }
                   end),
                   on_conflict: :nothing
                 )
               end

               result =
                 Repo.query!(
                   """
                   UPDATE marketing_previews SET eligible_count=$2, cursor_client_id=$3,
                     status=$4, completed_at=$5
                   WHERE policy_id=$1 AND request_id=$6 AND policy_revision=$7 AND
                     segment_revision=$8 AND feature_generation=$9 AND
                     segment_snapshot_id IS NOT DISTINCT FROM $10 AND status='pending'
                   """,
                   [
                     policy_raw,
                     next_count,
                     if(done or ids == [], do: nil, else: Ecto.UUID.dump!(List.last(ids))),
                     if(done, do: "ready", else: "pending"),
                     if(done, do: now, else: nil),
                     request_raw,
                     revision,
                     segment_revision,
                     feature_generation,
                     snapshot_raw
                   ]
                 )

               if result.num_rows != 1, do: Repo.rollback(:stale)

               if done, do: Segments.release_snapshot("marketing_preview", policy_id)

               :ok
             end) do
          {:ok, :ok} ->
            if length(ids) < @page do
              pending_or_done()
            else
              {:snooze, 1}
            end

          {:error, :stale} ->
            stale(
              policy_id,
              request_raw,
              revision,
              segment_revision,
              feature_generation,
              snapshot_raw,
              context
            )

          error ->
            error
        end
    end
  end

  defp stale(
         policy_id,
         request_raw,
         revision,
         segment_revision,
         feature_generation,
         snapshot_raw,
         context
       ) do
    case Background.publish(context, fn ->
           result =
             Repo.query!(
               """
               DELETE FROM marketing_previews WHERE policy_id=$1 AND request_id=$2 AND policy_revision=$3
                 AND segment_revision=$4 AND feature_generation=$5
                 AND segment_snapshot_id IS NOT DISTINCT FROM $6
               """,
               [
                 Ecto.UUID.dump!(policy_id),
                 request_raw,
                 revision,
                 segment_revision,
                 feature_generation,
                 snapshot_raw
               ]
             )

           if result.num_rows == 1,
             do: Segments.release_snapshot("marketing_preview", policy_id)
         end) do
      {:ok, _} -> pending_or_done()
      error -> error
    end
  end

  defp pending_or_done do
    if next_preview(), do: {:snooze, 1}, else: :ok
  end

  defp cleanup_or_done(context) do
    case Background.publish(context, fn ->
           Repo.query!("""
           DELETE FROM marketing_baseline_members WHERE ctid IN (
             SELECT b.ctid FROM marketing_baseline_members b
             JOIN marketing_policies m ON m.id=b.policy_id
             LEFT JOIN marketing_previews p ON p.policy_id=b.policy_id AND p.request_id=b.request_id
             WHERE NOT (m.baseline_complete=false AND m.baseline_snapshot_id=b.request_id)
               AND NOT (m.status='draft' AND p.status IN ('pending','ready'))
             LIMIT 50
           )
           """).num_rows
         end) do
      {:ok, 0} -> :ok
      {:ok, _} -> {:snooze, 1}
      error -> error
    end
  end
end
