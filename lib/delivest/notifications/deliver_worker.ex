defmodule Delivest.Notifications.DeliverWorker do
  @moduledoc "External delivery lane; an unknown provider result is never retried blindly."
  use Oban.Worker, queue: :notifications, max_attempts: 1
  import Ecto.Query

  alias Delivest.{Features, Notifications, Repo}
  alias Delivest.Notifications.Intent

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"intent_id" => id} = args}) do
    claimed =
      case Repo.get(Intent, id) |> Repo.preload(:notification) do
        %Intent{notification: notice} ->
          generation = %{
            franchise: args["generation_franchise"],
            branch: args["generation_branch"]
          }

          if generation == %{
               franchise: notice.notification_generation_franchise,
               branch: notice.notification_generation_branch
             } do
            Features.with_enabled_many(Notifications.send_locks(notice), fn ->
              claim(id, job_id)
            end)
          else
            {:error, :disabled}
          end

        _ ->
          {:ok, nil}
      end

    case claimed do
      {:ok, %Intent{} = intent} ->
        notice = intent.notification

        cond do
          not current_generation?(args, notice) ->
            finish(intent, :canceled, "feature_disabled")

          not Notifications.current_source?(notice, :send) ->
            finish(intent, :canceled, "source_inactive")

          intent.channel == "push" and not Notifications.consent?(notice.client_id, :push) ->
            finish(intent, :skipped, "no_consent")

          true ->
            {status, reason} = send_intent(intent)
            finish(intent, status, reason)
        end

      {:ok, nil} ->
        :ok

      {:error, :disabled} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp claim(id, job_id) do
    case Repo.one(
           from i in Intent,
             where: i.id == ^id and i.status == "queued" and i.job_id == ^job_id,
             lock: "FOR UPDATE",
             preload: :notification
         ) do
      %Intent{} = intent ->
        notice = intent.notification

        cond do
          not Notifications.current_source?(notice, :send) ->
            finish(intent, :canceled, "source_inactive")
            nil

          intent.channel == "push" and not Notifications.consent?(notice.client_id, :push) ->
            finish(intent, :skipped, "no_consent")
            nil

          true ->
            Repo.update!(Ecto.Changeset.change(intent, status: "inflight"))
        end

      _ ->
        nil
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

  defp send_intent(%Intent{channel: "sms"}), do: {:skipped, "provider_unconfigured"}
  defp send_intent(%Intent{channel: "in_app"}), do: {:sent, nil}

  defp finish(intent, status, reason) do
    Repo.update!(Ecto.Changeset.change(intent, status: to_string(status), last_error: reason))
    :ok
  end
end
