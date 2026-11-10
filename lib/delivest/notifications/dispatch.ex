defmodule Delivest.Notifications.Dispatch do
  @moduledoc "Bounded planner for durable customer notification delivery."
  import Ecto.Query
  alias Delivest.{Background, Features, Notifications, Repo}
  alias Delivest.Notifications.{DeliverWorker, Intent, PushDelivery, PushDeliveryWorker}
  alias Delivest.Push.ClientSubscription

  @batch 50
  @unknown_after_seconds 300

  def perform(:franchise, context) do
    with :ok <- Background.checkpoint(context),
         {:ok, _} <- Background.publish(context, fn -> recover_abandoned() end) do
      now = DateTime.utc_now()

      ids =
        Repo.all(
          from i in Intent,
            where: i.status == "pending" and i.due_at <= ^now,
            order_by: [asc: i.due_at, asc: i.id],
            limit: @batch,
            select: i.id
        )

      Enum.reduce_while(ids, :ok, fn id, _ ->
        with :ok <- Background.checkpoint(context), :ok <- plan(id, context) do
          {:cont, :ok}
        else
          error -> {:halt, error}
        end
      end)
    end
  end

  def perform(_, _), do: {:error, :invalid_scope}

  def on_disable(:franchise) do
    cancel_intents(from i in Intent, where: i.status in ["pending", "queued"])
    cancel_jobs(nil)
  end

  def on_disable({:branch, branch_id}) do
    cancel_intents(
      from i in Intent,
        join: n in assoc(i, :notification),
        where: n.branch_id == ^branch_id and i.status in ["pending", "queued"]
    )

    cancel_jobs("branch:" <> branch_id)
  end

  def on_source_disable(:franchise) do
    cancel_source_intents(
      from i in Intent,
        join: n in assoc(i, :notification),
        where: n.source_feature == "marketing_policies" and i.status in ["pending", "queued"]
    )

    cancel_source_jobs(nil)
  end

  def on_source_disable({:branch, branch_id}) do
    cancel_source_intents(
      from i in Intent,
        join: n in assoc(i, :notification),
        where:
          n.source_feature == "marketing_policies" and n.branch_id == ^branch_id and
            i.status in ["pending", "queued"]
    )

    cancel_source_jobs("branch:" <> branch_id)
  end

  defp cancel_source_intents(query) do
    Repo.update_all(query, set: [status: "canceled", last_error: "source_feature_disabled"])
    :ok
  end

  defp cancel_source_jobs(scope_key) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    query =
      from j in Oban.Job,
        where:
          j.state in ["available", "scheduled", "retryable"] and
            fragment("?->>'source_feature' = 'marketing_policies'", j.args)

    query =
      if scope_key,
        do: where(query, [j], fragment("?->>'scope_key' = ?", j.args, ^scope_key)),
        else: query

    Repo.update_all(query, set: [state: "cancelled", cancelled_at: now])
    :ok
  end

  defp cancel_jobs(scope_key) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    query =
      from j in Oban.Job,
        where:
          j.state in ["available", "scheduled", "retryable"] and
            fragment("?->>'optional_feature' = 'notifications'", j.args)

    query =
      if scope_key,
        do: where(query, [j], fragment("?->>'scope_key' = ?", j.args, ^scope_key)),
        else: query

    Repo.update_all(query, set: [state: "cancelled", cancelled_at: now])
    :ok
  end

  defp cancel_intents(query) do
    Repo.update_all(query, set: [status: "canceled", last_error: "feature_disabled"])
    :ok
  end

  defp recover_abandoned do
    cutoff = DateTime.add(DateTime.utc_now(), -@unknown_after_seconds, :second)

    stale_intent_ids =
      Repo.all(
        from i in Intent,
          where: i.status == "inflight" and i.updated_at < ^cutoff,
          order_by: [asc: i.updated_at, asc: i.id],
          limit: 50,
          select: i.id
      )

    Repo.update_all(
      from(i in Intent, where: i.id in ^stale_intent_ids and i.status == "inflight"),
      set: [status: "unknown", last_error: "delivery_interrupted"]
    )

    terminal = ["cancelled", "discarded", "completed"]

    intent_ids =
      Repo.all(
        from i in Intent,
          left_join: j in Oban.Job,
          on: j.id == i.job_id,
          where:
            i.status == "queued" and i.channel != "push" and
              (is_nil(j.id) or j.state in ^terminal),
          order_by: [asc: i.updated_at, asc: i.id],
          limit: 50,
          select: i.id
      )

    Repo.update_all(from(i in Intent, where: i.id in ^intent_ids and i.status == "queued"),
      set: [status: "canceled", last_error: "job_terminal_before_claim"]
    )

    queued_delivery_ids =
      Repo.all(
        from d in PushDelivery,
          join: i in Intent,
          on: i.id == d.intent_id,
          left_join: j in Oban.Job,
          on: j.id == d.job_id,
          where:
            d.status == "queued" and
              (i.status == "canceled" or is_nil(j.id) or j.state in ^terminal),
          order_by: [asc: d.updated_at, asc: d.id],
          limit: 50,
          select: d.id
      )

    {_, canceled_intent_ids} =
      Repo.update_all(
        from(d in PushDelivery,
          where: d.id in ^queued_delivery_ids and d.status == "queued",
          select: d.intent_id
        ),
        set: [status: "canceled", last_error: "job_terminal_before_claim"]
      )

    stale_ids =
      Repo.all(
        from d in PushDelivery,
          where: d.status == "inflight" and d.updated_at < ^cutoff,
          limit: 50,
          select: d.id
      )

    {_, delivery_ids} =
      Repo.update_all(
        from(d in PushDelivery,
          where: d.id in ^stale_ids and d.status == "inflight",
          select: d.intent_id
        ),
        set: [status: "unknown", last_error: "delivery_interrupted"]
      )

    Enum.each(Enum.uniq(delivery_ids ++ canceled_intent_ids), &finalize_push/1)
  end

  defp plan(id, context) do
    case Repo.get(Intent, id) |> Repo.preload(:notification) do
      %Intent{status: "pending", notification: notice} ->
        scope = {:branch, notice.branch_id}

        case Features.snapshot("notifications", scope) do
          {:ok, generation} ->
            case Background.publish(
                   context,
                   scope,
                   generation,
                   Notifications.send_locks(notice),
                   fn -> claim(id, generation) end
                 ) do
              {:ok, _} -> :ok
              {:error, :disabled} -> cancel_stale_source(id, context, scope, generation)
              error -> error
            end

          {:error, :disabled} ->
            :ok
        end

      _ ->
        :ok
    end
  end

  defp cancel_stale_source(id, context, scope, generation) do
    case Background.publish(context, scope, generation, fn ->
           intent =
             Repo.one(
               from i in Intent,
                 where: i.id == ^id and i.status == "pending",
                 lock: "FOR UPDATE",
                 preload: :notification
             )

           if intent do
             notice = intent.notification
             source_lock = hd(Notifications.send_locks(notice))
             {feature, source_scope, source_token} = source_lock

             unless Features.still_enabled?(feature, source_scope, source_token) do
               Repo.update!(
                 Ecto.Changeset.change(intent,
                   status: "canceled",
                   last_error: "source_generation_changed"
                 )
               )
             end
           end
         end) do
      {:ok, _} -> :ok
      {:error, :disabled} -> :ok
      error -> error
    end
  end

  defp claim(id, generation) do
    intent =
      Repo.one(
        from i in Intent,
          where: i.id == ^id and i.status == "pending",
          lock: "FOR UPDATE",
          preload: :notification
      )

    if intent do
      notice = intent.notification

      cond do
        not Notifications.current_source?(notice, :send) ->
          Repo.update!(
            Ecto.Changeset.change(intent, status: "canceled", last_error: "source_inactive")
          )

        intent.channel == "push" and not Notifications.consent?(notice.client_id, :push) ->
          Repo.update!(Ecto.Changeset.change(intent, status: "skipped", last_error: "no_consent"))

        intent.channel == "push" ->
          plan_push(intent, generation)

        true ->
          job =
            %{
              intent_id: intent.id,
              optional_feature: "notifications",
              source_feature: notice.source_feature,
              scope_key: "branch:" <> notice.branch_id,
              generation_franchise: generation.franchise,
              generation_branch: generation.branch
            }
            |> DeliverWorker.new()
            |> Oban.insert!()

          Repo.update!(Ecto.Changeset.change(intent, status: "queued", job_id: job.id))
      end
    end
  end

  defp plan_push(intent, generation) do
    notice = intent.notification
    cursor = intent.fanout_cursor

    subscriptions_query =
      from s in ClientSubscription,
        where: s.client_id == ^notice.client_id,
        order_by: [asc: s.id],
        limit: 51,
        select: s.id

    subscriptions_query =
      if cursor,
        do: where(subscriptions_query, [s], s.id > ^cursor),
        else: subscriptions_query

    subscriptions = Repo.all(subscriptions_query)

    batch = Enum.take(subscriptions, 50)

    Enum.each(batch, fn subscription_id ->
      delivery =
        %PushDelivery{intent_id: intent.id}
        |> PushDelivery.changeset(%{subscription_id: subscription_id})
        |> Repo.insert!()

      job =
        %{
          delivery_id: delivery.id,
          optional_feature: "notifications",
          source_feature: notice.source_feature,
          scope_key: "branch:" <> notice.branch_id,
          generation_franchise: generation.franchise,
          generation_branch: generation.branch
        }
        |> PushDeliveryWorker.new()
        |> Oban.insert!()

      Repo.update!(Ecto.Changeset.change(delivery, job_id: job.id))
    end)

    complete = length(subscriptions) <= 50

    status =
      cond do
        complete and batch == [] and is_nil(cursor) -> "skipped"
        complete -> "queued"
        true -> "pending"
      end

    Repo.update!(
      Ecto.Changeset.change(intent,
        status: status,
        fanout_complete: complete,
        fanout_cursor: List.last(batch) || cursor,
        last_error: if(status == "skipped", do: "no_subscription", else: nil)
      )
    )
  end

  def finalize_push(intent_id) do
    Repo.transaction(fn ->
      intent = Repo.one(from i in Intent, where: i.id == ^intent_id, lock: "FOR UPDATE")

      if intent && intent.channel == "push" && intent.fanout_complete && intent.status == "queued" do
        [[pending, unknown, sent]] =
          Repo.query!(
            """
            SELECT count(*) FILTER (WHERE status IN ('queued','inflight')),
                   count(*) FILTER (WHERE status='unknown'),
                   count(*) FILTER (WHERE status='sent')
            FROM customer_notification_push_deliveries WHERE intent_id=$1
            """,
            [Ecto.UUID.dump!(intent_id)]
          ).rows

        if pending == 0 do
          {status, reason} =
            cond do
              unknown > 0 -> {"unknown", "push_result_unknown"}
              sent > 0 -> {"sent", nil}
              true -> {"skipped", "no_successful_subscription"}
            end

          Repo.update!(Ecto.Changeset.change(intent, status: status, last_error: reason))
        end
      end
    end)

    :ok
  end
end
