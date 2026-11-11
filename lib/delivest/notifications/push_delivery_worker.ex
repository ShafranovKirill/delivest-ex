defmodule Delivest.Notifications.PushDeliveryWorker do
  @moduledoc "One durable browser push attempt per job. An interrupted HTTP attempt stays unknown."
  use Oban.Worker, queue: :notifications, max_attempts: 1
  import Ecto.Query

  alias Delivest.{Features, Notifications, Repo}
  alias Delivest.Notifications.{Dispatch, Intent, MarketingPushLimiter, PushDelivery}
  alias Delivest.Push.ClientSubscription

  @impl Oban.Worker
  def timeout(_job), do: 30_000

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"delivery_id" => id} = args}) do
    claimed =
      case Repo.get(PushDelivery, id) |> Repo.preload(intent: :notification) do
        %PushDelivery{intent: %Intent{notification: notice}} ->
          generation = %{
            franchise: args["generation_franchise"],
            branch: args["generation_branch"]
          }

          if generation == %{
               franchise: notice.notification_generation_franchise,
               branch: notice.notification_generation_branch
             } do
            Features.with_enabled_many(Notifications.send_locks(notice), fn ->
              claim(id, job_id, args)
            end)
          else
            {:error, :disabled}
          end

        _ ->
          {:ok, nil}
      end

    case claimed do
      {:ok, %PushDelivery{} = delivery} ->
        notice = delivery.intent.notification

        {status, reason} =
          cond do
            not current_generation?(args, notice) -> {"canceled", "feature_disabled"}
            not Notifications.current_source?(notice, :send) -> {"canceled", "source_inactive"}
            not Notifications.consent?(notice.client_id, :push) -> {"skipped", "no_consent"}
            true -> send_delivery(delivery, notice)
          end

        Repo.update_all(
          from(d in PushDelivery, where: d.id == ^delivery.id and d.status == "inflight"),
          set: [status: status, last_error: reason]
        )

        Dispatch.finalize_push(delivery.intent_id)
        :ok

      {:ok, nil} ->
        finalize_if_present(id)

      {:error, :disabled} ->
        finalize_if_present(id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp finalize_if_present(id) do
    case Repo.get(PushDelivery, id) do
      nil -> :ok
      delivery -> Dispatch.finalize_push(delivery.intent_id)
    end
  end

  defp claim(id, job_id, args) do
    delivery = Repo.get(PushDelivery, id) |> Repo.preload(intent: :notification)

    if delivery do
      intent = Repo.one(from i in Intent, where: i.id == ^delivery.intent_id, lock: "FOR UPDATE")

      row =
        Repo.one(
          from d in PushDelivery,
            where: d.id == ^id and d.status == "queued" and d.job_id == ^job_id,
            lock: "FOR UPDATE",
            preload: [intent: :notification]
        )

      cond do
        is_nil(row) or is_nil(intent) or intent.status not in ["pending", "queued"] ->
          nil

        not current_generation?(args, row.intent.notification) ->
          nil

        not Notifications.current_source?(row.intent.notification, :send) ->
          Repo.update!(
            Ecto.Changeset.change(row, status: "canceled", last_error: "source_inactive")
          )

          nil

        not Notifications.consent?(row.intent.notification.client_id, :push) ->
          Repo.update!(Ecto.Changeset.change(row, status: "skipped", last_error: "no_consent"))
          nil

        is_nil(
          Repo.get_by(ClientSubscription,
            id: row.subscription_id,
            client_id: row.intent.notification.client_id
          )
        ) ->
          Repo.update!(
            Ecto.Changeset.change(row, status: "skipped", last_error: "subscription_removed")
          )

          nil

        true ->
          claim_frequency(row)
      end
    end
  end

  defp claim_frequency(row) do
    notice = row.intent.notification

    result =
      if notice.source_feature == "marketing_policies" do
        MarketingPushLimiter.claim(row.intent_id, notice.client_id)
      else
        :reserved
      end

    case result do
      :reserved ->
        Repo.update!(Ecto.Changeset.change(row, status: "inflight"))

      :stale ->
        Repo.update!(
          Ecto.Changeset.change(row, status: "skipped", last_error: "stale_reservation")
        )

        nil

      :limited ->
        Repo.update_all(
          from(d in PushDelivery, where: d.intent_id == ^row.intent_id and d.status == "queued"),
          set: [status: "skipped", last_error: "frequency_limit"]
        )

        Repo.update!(
          Ecto.Changeset.change(row.intent, status: "skipped", last_error: "frequency_limit")
        )

        nil
    end
  end

  defp send_delivery(delivery, notice) do
    case Repo.get_by(ClientSubscription,
           id: delivery.subscription_id,
           client_id: notice.client_id
         ) do
      nil ->
        {"skipped", "subscription_removed"}

      subscription ->
        payload = %{title: notice.title, body: notice.body, tag: "notification:" <> notice.id}

        case Notifications.deliver_push(subscription, payload, :marketing,
               retry: false,
               receive_timeout: 10_000,
               connect_options: [timeout: 5_000]
             ) do
          :ok ->
            {"sent", nil}

          :expired ->
            Repo.delete_all(
              from s in ClientSubscription,
                where:
                  s.id == ^subscription.id and s.client_id == ^notice.client_id and
                    s.endpoint == ^subscription.endpoint and s.p256dh == ^subscription.p256dh and
                    s.auth == ^subscription.auth
            )

            {"skipped", "subscription_expired"}

          _ ->
            {"unknown", "push_result_unknown"}
        end
    end
  end

  defp current_generation?(args, notice) do
    args["optional_feature"] == "notifications" and
      args["source_feature"] == notice.source_feature and
      args["scope_key"] == "branch:" <> notice.branch_id and
      Enum.all?(Notifications.send_locks(notice), fn {feature, scope, token} ->
        Features.still_enabled?(feature, scope, token)
      end)
  end
end
