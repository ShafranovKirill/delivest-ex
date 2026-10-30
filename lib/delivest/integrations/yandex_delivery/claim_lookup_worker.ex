defmodule Delivest.Integrations.YandexDelivery.ClaimLookupWorker do
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Delivest.{Couriers, Repo}
  alias Delivest.Couriers.Delivery
  alias Delivest.Integrations.Journal
  alias Delivest.Integrations.Poller
  alias Delivest.Integrations.YandexDelivery
  alias Delivest.Integrations.YandexDelivery.Api

  @pause 30
  @window 300

  def enqueue(%Delivery{} = delivery, order) do
    %{delivery_id: delivery.id, number: order.number, started_at: System.os_time(:second)}
    |> new(schedule_in: pause())
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"delivery_id" => id, "number" => number, "started_at" => started}
      }) do
    case Repo.get(Delivery, id) do
      %Delivery{external_id: nil, status: :searching} = delivery ->
        lookup(delivery, number, started)

      _other ->
        :ok
    end
  end

  defp lookup(delivery, number, started) do
    token = YandexDelivery.settings(delivery.branch_id).token

    result =
      Journal.scope([branch_id: delivery.branch_id, order_id: delivery.order_id], fn ->
        Api.search(token, number)
      end)

    case result do
      {:ok, %{"claims" => [%{"id" => claim_id} | _]}} -> attach(delivery, claim_id)
      _none -> retry_or_give_up(delivery, number, started)
    end
  end

  defp attach(delivery, claim_id) do
    delivery |> Delivery.provider_changeset(%{external_id: claim_id}) |> Repo.update!()
    Poller.enqueue(YandexDelivery.Poller, delivery.branch_id)
    :ok
  end

  defp retry_or_give_up(delivery, number, started) do
    if System.os_time(:second) - started >= window() do
      Couriers.give_up(delivery)
      :ok
    else
      %{delivery_id: delivery.id, number: number, started_at: started}
      |> new(schedule_in: pause())
      |> Oban.insert()

      :ok
    end
  end

  defp pause, do: Application.get_env(:delivest, :yandex_delivery_lookup_pause, @pause)
  defp window, do: Application.get_env(:delivest, :yandex_delivery_lookup_window, @window)
end
