defmodule Delivest.Loyalty.ExpiryDeliveryWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  import Ecto.Query

  alias Delivest.Loyalty.{ExpiryDelivery, ExpiryNoticeWorker}
  alias Delivest.Push.ClientSubscription
  alias Delivest.Repo

  @stale_seconds 120

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)

  def sweep_stale do
    now = DateTime.utc_now(:second)
    cutoff = DateTime.add(now, -@stale_seconds, :second)

    ExpiryDelivery
    |> where([d], d.status == :sending and d.updated_at <= ^cutoff)
    |> select([d], d.id)
    |> Repo.all()
    |> Enum.each(fn id ->
      ExpiryDelivery
      |> where([d], d.id == ^id and d.status == :sending and d.updated_at <= ^cutoff)
      |> Repo.update_all(set: [status: :unknown, last_error: "stale:#{id}", updated_at: now])
    end)

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => id}} = job) do
    now = DateTime.utc_now(:second)

    {claimed, _} =
      ExpiryDelivery
      |> where([d], d.id == ^id and d.status == :pending)
      |> Repo.update_all(set: [status: :sending, updated_at: now], inc: [attempts: 1])

    case {claimed, Repo.get(ExpiryDelivery, id)} do
      {1, %ExpiryDelivery{} = delivery} -> send_delivery(delivery, job)
      {0, %ExpiryDelivery{status: :sending} = delivery} -> mark_stale(delivery, now)
      _ -> :ok
    end
  end

  defp send_delivery(delivery, job) do
    notification = Repo.get!(Delivest.Loyalty.ExpiryNotification, delivery.notification_id)

    if notification.expires_at &&
         DateTime.compare(DateTime.utc_now(), notification.expires_at) != :lt do
      finish(delivery, :expired, "stars_expired")
    else
      case Repo.get_by(ClientSubscription,
             id: delivery.subscription_id,
             client_id: notification.client_id
           ) do
        nil ->
          finish(delivery, :expired, "subscription_missing")

        subscription ->
          payload =
            ExpiryNoticeWorker.message(
              subscription.locale || "ru",
              notification.branch_id,
              notification.stars,
              notification.expires_on
            )

          result =
            try do
              Delivest.Notifications.deliver_push(subscription, payload, :account,
                retry: false,
                receive_timeout: 10_000
              )
            rescue
              _error -> {:error, :transport_unknown}
            catch
              _kind, _reason -> {:error, :transport_unknown}
            end

          handle_result(result, delivery, subscription, job)
      end
    end
  end

  defp handle_result(:ok, delivery, _subscription, _job),
    do: finish(delivery, :delivered, nil)

  defp handle_result(:expired, delivery, subscription, _job) do
    ClientSubscription
    |> where([s], s.id == ^subscription.id and s.client_id == ^subscription.client_id)
    |> Repo.delete_all()

    finish(delivery, :expired, "subscription_expired")
  end

  defp handle_result({:error, {:http_error, status}}, delivery, _subscription, job)
       when status == 429 or status in 500..599 do
    if job.attempt >= job.max_attempts do
      finish(delivery, :failed, "http_#{status}")
      {:error, {:http_error, status}}
    else
      finish(delivery, :pending, "http_#{status}")
      {:error, {:http_error, status}}
    end
  end

  defp handle_result({:error, {:http_error, status}}, delivery, _subscription, _job),
    do: finish(delivery, :rejected, "http_#{status}")

  defp handle_result({:error, _reason}, delivery, _subscription, _job) do
    finish(delivery, :unknown, "unconfirmed:#{delivery.id}")
    {:cancel, "expiry delivery unconfirmed: #{delivery.id}"}
  end

  defp mark_stale(delivery, now) do
    age = DateTime.diff(now, delivery.updated_at, :second)

    if age >= @stale_seconds do
      ExpiryDelivery
      |> where([d], d.id == ^delivery.id and d.status == :sending)
      |> Repo.update_all(
        set: [status: :unknown, last_error: "stale:#{delivery.id}", updated_at: now]
      )

      {:cancel, "expiry delivery unconfirmed: #{delivery.id}"}
    else
      {:snooze, @stale_seconds - age}
    end
  end

  defp finish(delivery, status, reason) do
    ExpiryDelivery
    |> where([d], d.id == ^delivery.id and d.status == :sending)
    |> Repo.update_all(
      set: [status: status, last_error: reason, updated_at: DateTime.utc_now(:second)]
    )

    :ok
  end
end
