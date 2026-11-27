defmodule Delivest.Integrations.YandexDelivery.ClaimLookupWorker do
  use Oban.Worker, queue: :default, max_attempts: 1
  import Ecto.Query

  alias Delivest.{Couriers, Repo}
  alias Delivest.Couriers.Delivery
  alias Delivest.Integrations.Journal
  alias Delivest.Integrations.StaffAccess
  alias Delivest.Integrations.Poller
  alias Delivest.Integrations.YandexDelivery
  alias Delivest.Integrations.YandexDelivery.Api

  @pause 30
  @window 300

  def enqueue(%Delivery{} = delivery, order) do
    if StaffAccess.allowed?(:yandex_delivery) do
      %{delivery_id: delivery.id, number: order.number, started_at: System.os_time(:second)}
      |> new(schedule_in: pause())
      |> Oban.insert()
    else
      {:error, :disabled}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"delivery_id" => id, "number" => number, "started_at" => started}
      }) do
    if StaffAccess.allowed?(:yandex_delivery),
      do: perform_enabled(id, number, started),
      else: {:cancel, :disabled}
  end

  defp perform_enabled(id, number, started) do
    case Repo.get(Delivery, id) do
      %Delivery{external_id: nil, status: :searching} = delivery ->
        lookup(delivery, number, started)

      %Delivery{external_id: nil, status: :picked_up, details: %{"manual_pickup" => true}} =
          delivery ->
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
    Repo.transaction(fn ->
      Repo.one!(
        from o in Delivest.Oms.Order, where: o.id == ^delivery.order_id, lock: "FOR UPDATE"
      )

      case Repo.one!(from d in Delivery, where: d.id == ^delivery.id, lock: "FOR UPDATE") do
        %Delivery{external_id: nil, status: status} = current
        when status in [:searching, :picked_up] ->
          current |> Delivery.provider_changeset(%{external_id: claim_id}) |> Repo.update!()

        _closed ->
          :ok
      end
    end)

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
