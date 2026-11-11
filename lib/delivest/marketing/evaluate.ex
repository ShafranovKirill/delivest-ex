defmodule Delivest.Marketing.Evaluate do
  @moduledoc "Fair, durable daily evaluation through the common Background scheduler."
  import Ecto.Query

  alias Delivest.{Background, Marketing, Repo, Segments}
  alias Delivest.Marketing.Policy
  alias Delivest.Segments.Segment

  @zero "00000000-0000-0000-0000-000000000000"
  @page 25

  def perform(:franchise, context) do
    with :ok <- Background.checkpoint(context) do
      case Background.publish(context, &next_policy/0) do
        {:ok, :done} ->
          :ok

        {:ok, {:ok, policy, run_id}} ->
          case evaluate_page(policy, run_id, context) do
            :ok -> {:snooze, 1}
            other -> other
          end

        error ->
          error
      end
    end
  end

  def perform(_, _), do: {:error, :invalid_scope}

  defp next_policy do
    Repo.transaction(fn ->
      Repo.insert_all("marketing_evaluation_states", [%{id: 1}], on_conflict: :nothing)

      [[run_id_raw, last_raw]] =
        Repo.query!(
          "SELECT run_id, last_policy_id FROM marketing_evaluation_states WHERE id=1 FOR UPDATE"
        ).rows

      run_id = if run_id_raw, do: Ecto.UUID.load!(run_id_raw), else: Ecto.UUID.generate()
      last = if last_raw, do: Ecto.UUID.load!(last_raw), else: @zero

      if run_id_raw == nil do
        Repo.query!(
          "UPDATE marketing_evaluation_states SET run_id=$1, started_at=now(), last_policy_id=NULL WHERE id=1",
          [Ecto.UUID.dump!(run_id)]
        )
      end

      query =
        from p in Policy,
          where:
            p.status in [:active, :initializing] and
              (is_nil(p.evaluated_run_id) or p.evaluated_run_id != ^run_id),
          order_by: [asc: p.id],
          limit: 1

      policy = Repo.one(where(query, [p], p.id > ^last)) || Repo.one(query)

      case policy do
        nil ->
          Repo.query!(
            "UPDATE marketing_evaluation_states SET run_id=NULL, last_policy_id=NULL WHERE id=1"
          )

          :done

        policy ->
          Repo.query!(
            "UPDATE marketing_evaluation_states SET last_policy_id=$1 WHERE id=1",
            [Ecto.UUID.dump!(policy.id)]
          )

          {:ok, policy, run_id}
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp evaluate_page(policy, run_id, context) do
    with :ok <- Background.checkpoint(context),
         %Segment{} = segment <- Repo.get(Segment, policy.segment_id) do
      cursor = policy.cursor_client_id || @zero
      snapshot = nil

      ids =
        if policy.status == :initializing do
          Repo.all(
            from c in "marketing_baseline_members",
              where:
                c.policy_id == type(^policy.id, :binary_id) and
                  c.request_id == type(^policy.baseline_snapshot_id, :binary_id) and
                  c.client_id > type(^cursor, :binary_id),
              order_by: [asc: c.client_id],
              limit: @page,
              select: type(c.client_id, :binary_id)
          )
        else
          Segments.published_member_page(segment, cursor, @page, snapshot)
        end

      selection =
        if policy.status == :initializing,
          do: %{eligible_ids: [], excluded_cycles: []},
          else: Marketing.candidate_state(policy, ids, DateTime.utc_now(:second))

      Enum.reduce_while(selection.eligible_ids, :ok, fn client_id, _ ->
        with :ok <- Background.checkpoint(context),
             :ok <- process_client(policy, client_id, context) do
          {:cont, :ok}
        else
          error -> {:halt, error}
        end
      end)
      |> case do
        :ok -> save_progress(policy, run_id, ids, selection.excluded_cycles, context)
        error -> error
      end
    else
      nil -> {:error, :missing_segment}
      error -> error
    end
  end

  defp process_client(policy, client_id, context) do
    case Marketing.issue(policy, client_id, context) do
      {:ok, _} ->
        :ok

      {:error, :stale} ->
        :ok

      {:error, :already_issued} ->
        :ok

      {:error, reason} when reason in [:promotion_unavailable, :points_unavailable] ->
        record_configuration_error(policy, reason, context)

      error ->
        error
    end
  end

  defp record_configuration_error(policy, reason, context) do
    case Background.publish(context, fn ->
           Repo.update_all(
             from(p in Policy,
               where: p.id == ^policy.id and p.revision == ^policy.revision
             ),
             set: [last_error: Atom.to_string(reason)]
           )

           :ok
         end) do
      {:ok, :ok} -> :ok
      error -> error
    end
  end

  defp save_progress(policy, run_id, ids, excluded_cycles, context) do
    case Background.publish(context, fn ->
           locked = Repo.one(from p in Policy, where: p.id == ^policy.id, lock: "FOR UPDATE")

           if locked && locked.revision == policy.revision && locked.status == policy.status do
             if excluded_cycles != [] do
               Repo.insert_all(
                 "marketing_exclusions",
                 Enum.map(excluded_cycles, fn {client_id, cycle_id} ->
                   %{
                     policy_id: Ecto.UUID.dump!(policy.id),
                     client_id: Ecto.UUID.dump!(client_id),
                     cycle_order_id: Ecto.UUID.dump!(cycle_id),
                     reason: "policy_exclusion",
                     inserted_at: DateTime.utc_now(:second)
                   }
                 end),
                 on_conflict: :nothing
               )
             end

             if locked.status == :initializing and ids != [] do
               Repo.query!(
                 """
                 INSERT INTO marketing_suppressions
                   (policy_id, client_id, cycle_order_id, reason, inserted_at)
                 SELECT policy_id, client_id, cycle_order_id, 'initial_future_only', now()
                 FROM marketing_baseline_members
                 WHERE policy_id=$1 AND request_id=$2 AND client_id=ANY($3::uuid[])
                 ON CONFLICT DO NOTHING
                 """,
                 [
                   Ecto.UUID.dump!(policy.id),
                   Ecto.UUID.dump!(policy.baseline_snapshot_id),
                   Enum.map(ids, &Ecto.UUID.dump!/1)
                 ]
               )
             end

             done = length(ids) < @page

             attrs =
               if done do
                 %{
                   cursor_client_id: nil,
                   evaluated_run_id: run_id,
                   baseline_complete: locked.status == :initializing or locked.baseline_complete,
                   status: if(locked.status == :initializing, do: :active, else: locked.status)
                 }
               else
                 %{cursor_client_id: List.last(ids)}
               end

             Repo.update!(Ecto.Changeset.change(locked, attrs))
           end

           :ok
         end) do
      {:ok, :ok} ->
        if policy.status == :initializing and length(ids) < @page, do: :ok

        :ok

      {:error, :disabled} ->
        {:error, :disabled}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
