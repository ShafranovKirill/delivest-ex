defmodule Delivest.Integrations.YandexDelivery do
  @behaviour Delivest.Couriers.Provider

  import Ecto.Query

  require Logger

  alias Delivest.{Couriers, Identity, Repo}
  alias Delivest.Couriers.Delivery
  alias Delivest.Identity.Branch
  alias Delivest.Integrations.Journal, as: RequestJournal
  alias Delivest.Integrations.{Error, Poller}
  alias Delivest.Integrations.YandexDelivery.{Api, Claim, ClaimLookupWorker, Journal, Settings}
  alias Delivest.Oms.{Order, Orders}

  @searching ~w(new estimating ready_for_approval accepted performer_lookup performer_draft)
  @assigned ~w(performer_found pickup_arrived ready_for_pickup_confirmation)
  @picked_up ~w(pickuped delivery_arrived ready_for_delivery_confirmation pay_waiting delivered)
  @lost ~w(performer_not_found cancelled_by_taxi)
  @failed ~w(failed estimating_failed)
  @cancelled ~w(cancelled cancelled_with_payment cancelled_with_items_on_hands)
  @returning ~w(returning return_arrived ready_for_return_confirmation returned returned_finish)
  @final ["delivered_finish", "returned_finish" | @lost ++ @failed ++ @cancelled]
  @stale_seconds 60
  @create_retries 2
  @retry_pause 2_000

  @impl true
  def key, do: :yandex

  @impl true
  def name, do: "Яндекс Доставка"

  @impl true
  def health_check(%Settings{} = settings) do
    if Settings.configured?(settings),
      do: with({:ok, _journal} <- Api.journal(settings.token, nil), do: :ok),
      else: {:error, :not_configured}
  end

  @impl true
  def classify_error({:yandex_delivery, status, code}) when is_integer(status),
    do: Error.classify({:http_error, status, code})

  def classify_error(reason), do: Error.classify(reason)

  def settings(branch_id) do
    case Identity.get_branch(branch_id, preload: :info) do
      {:ok, %Branch{info: %{yandex_delivery: %Settings{} = settings}}} -> settings
      _other -> %Settings{}
    end
  end

  def change_settings(%Settings{} = settings, attrs \\ %{}),
    do: Settings.changeset(settings, attrs)

  def update_settings(staff, branch_id, attrs) do
    with {:ok, branch} <- Identity.get_branch(branch_id, preload: :info),
         {:ok, branch} <-
           Identity.update_integrations(staff, branch, %{"yandex_delivery" => attrs}) do
      {:ok, branch.info.yandex_delivery}
    else
      {:error, :info, changeset} ->
        {:error, Ecto.Changeset.get_change(changeset, :yandex_delivery)}

      {:error, _step, changeset} ->
        {:error, changeset}

      error ->
        error
    end
  end

  def state(status) when status in @searching, do: :searching
  def state(status) when status in @assigned, do: :assigned
  def state(status) when status in @picked_up, do: :picked_up
  def state("delivered_finish"), do: :delivered
  def state(status) when status in @lost, do: :lost
  def state(status) when status in @failed, do: :failed
  def state(status) when status in @cancelled, do: :cancelled
  def state(status) when status in @returning, do: :returning
  def state(_status), do: :searching

  def returning?(%Delivery{provider: :yandex, details: %{"status" => status}}),
    do: status in @returning

  def returning?(_delivery), do: false

  @impl true
  def start(%Delivery{} = delivery, %Order{} = order) do
    RequestJournal.scope([branch_id: order.branch_id, order_id: order.id], fn ->
      create_claim(delivery, Repo.preload(order, [:client, items: :modifiers]))
    end)
  end

  defp create_claim(delivery, order) do
    with {:ok, branch} <- Identity.get_branch(order.branch_id, preload: :info),
         %Settings{} = settings <- configured(branch),
         {:ok, body} <- Claim.build(order, branch, settings),
         {:ok, claim} <- create_with_retry(settings.token, delivery.id, body, @create_retries) do
      switch_to_card(order)
      Poller.enqueue(__MODULE__.Poller, order.branch_id)
      {:ok, %{external_id: claim["id"], details: details(claim)}}
    else
      {:error, reason} = error ->
        if ambiguous?(reason) do
          ClaimLookupWorker.enqueue(delivery, order)
          {:ok, %{details: %{"lookup" => true}}}
        else
          error
        end

      other ->
        other
    end
  end

  defp create_with_retry(token, request_id, body, retries) do
    case Api.create(token, request_id, body) do
      {:ok, %{"id" => _id}} = ok ->
        ok

      {:error, reason} = error ->
        if retries > 0 and ambiguous?(reason) do
          Process.sleep(retry_pause())
          create_with_retry(token, request_id, body, retries - 1)
        else
          error
        end

      {:ok, body} ->
        {:error, {:yandex_delivery, :unexpected, body}}
    end
  end

  def ambiguous?({:connection_error, _message, _reason}), do: true
  def ambiguous?({:yandex_delivery, status, _code}) when is_integer(status), do: status >= 500
  def ambiguous?(_reason), do: false

  defp retry_pause,
    do: Application.get_env(:delivest, :yandex_delivery_retry_pause, @retry_pause)

  def estimate(%Order{} = order) do
    RequestJournal.scope([branch_id: order.branch_id, order_id: order.id], fn ->
      with {:ok, branch} <- Identity.get_branch(order.branch_id, preload: :info),
           %Settings{} = settings <- configured(branch),
           {:ok, body} <- Claim.estimate(order, branch, settings),
           {:ok, response} <- Api.calculate(settings.token, body) do
        offer(response, order)
      else
        {:error, _reason} = error -> error
        other -> other
      end
    end)
  end

  defp offer(%{"offers" => [_ | _] = offers}, order) do
    offer = Enum.min_by(offers, &cents(&1["price"]["total_price"]))
    price = cents(offer["price"]["total_price"])

    {:ok,
     %{
       price: price,
       pickup_interval: offer["pickup_interval"],
       delivery_interval: offer["delivery_interval"],
       loss: max(price - (order.delivery_amount || 0), 0)
     }}
  end

  defp offer(_response, _order), do: {:error, :no_offers}

  defp cents(price) when is_binary(price) do
    {value, _rest} = Float.parse(price)
    round(value * 100)
  end

  defp cents(_price), do: 0

  @impl true
  def cancel(%Delivery{external_id: nil}), do: :ok
  def cancel(%Delivery{details: %{"status" => status}}) when status in @final, do: :ok

  def cancel(%Delivery{} = delivery) do
    RequestJournal.scope([branch_id: delivery.branch_id, order_id: delivery.order_id], fn ->
      cancel_claim(delivery)
    end)
  end

  defp cancel_claim(%Delivery{external_id: claim_id} = delivery) do
    token = settings(delivery.branch_id).token

    with {:ok, %{"cancel_state" => cancel_state} = info} <- Api.cancel_info(token, claim_id),
         :ok <- confirmed(delivery, cancel_state, info),
         {:ok, %{"version" => version}} <- Api.info(token, claim_id),
         {:ok, _response} <- Api.cancel(token, claim_id, version, cancel_state) do
      :ok
    else
      {:error, {:yandex_delivery, _status, "inappropriate_status"}} -> :ok
      error -> error
    end
  end

  defp confirmed(%Delivery{details: details}, "paid", info) do
    if details["cancel_price"], do: :ok, else: {:error, {:paid_cancel, cents(info["price"])}}
  end

  defp confirmed(_delivery, _state, _info), do: :ok

  @impl true
  def order_ready(%Delivery{external_id: nil}), do: :ok
  def order_ready(%Delivery{details: %{"status" => status}}) when status in @final, do: :ok

  def order_ready(%Delivery{external_id: claim_id} = delivery) do
    RequestJournal.scope([branch_id: delivery.branch_id, order_id: delivery.order_id], fn ->
      case Api.set_point_ready(settings(delivery.branch_id).token, claim_id) do
        {:ok, _response} -> :ok
        {:error, {:yandex_delivery, _status, "inappropriate_status"}} -> :ok
        error -> error
      end
    end)
  end

  def poll(branch_id) do
    settings = settings(branch_id)

    case active(branch_id) do
      [] ->
        :done

      deliveries ->
        if Settings.configured?(settings),
          do:
            RequestJournal.scope([branch_id: branch_id], fn ->
              poll(branch_id, settings, deliveries)
            end),
          else: :done
    end
  end

  defp poll(branch_id, settings, deliveries) do
    journal = Repo.get(Journal, branch_id) || %Journal{branch_id: branch_id}

    with {:ok, %{"cursor" => cursor} = response} <- Api.journal(settings.token, journal.cursor) do
      changed = response |> Map.get("events", []) |> MapSet.new(& &1["claim_id"])

      deliveries
      |> Enum.filter(&(MapSet.member?(changed, &1.external_id) or stale?(&1)))
      |> Enum.each(&sync(&1, settings))

      journal |> Ecto.Changeset.change(cursor: cursor) |> Repo.insert_or_update!()
      if active(branch_id) == [], do: :done, else: :more
    end
  end

  def sync(%Delivery{} = delivery, %Settings{} = settings) do
    RequestJournal.scope([branch_id: delivery.branch_id, order_id: delivery.order_id], fn ->
      sync_claim(delivery, settings)
    end)
  end

  defp sync_claim(%Delivery{external_id: claim_id} = delivery, %Settings{token: token}) do
    with {:ok, %{"status" => status} = claim} <- Api.info(token, claim_id) do
      if status == "ready_for_approval", do: accept(token, claim)

      details =
        claim
        |> details()
        |> Map.merge(courier_details(token, claim, delivery.details))
        |> Map.merge(point_eta(token, claim))

      Couriers.report(delivery, state(status), details)
    else
      {:error, reason} = error ->
        Logger.warning("delivery #{delivery.id}: yandex claim sync failed (#{inspect(reason)})")
        error
    end
  end

  defp accept(token, %{"id" => claim_id, "version" => version}) do
    with {:error, reason} <- Api.accept(token, claim_id, version) do
      Logger.warning("yandex claim #{claim_id}: accept failed (#{inspect(reason)})")
    end
  end

  defp details(claim) do
    %{
      "status" => claim["status"],
      "price" => price(claim["pricing"]),
      "eta" => claim["eta"],
      "performer" => performer(claim["performer_info"]),
      "synced_at" => DateTime.to_iso8601(DateTime.utc_now())
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp courier_details(token, %{"status" => status} = claim, known)
       when status in @assigned or status in @picked_up do
    performer = performer(claim["performer_info"])

    if performer == known["performer"] and known["phone"],
      do: Map.take(known, ["phone", "tracking_url"]),
      else: %{"phone" => phone(token, claim), "tracking_url" => tracking_url(token, claim)}
  end

  defp courier_details(_token, _claim, known), do: Map.take(known, ["phone", "tracking_url"])

  defp point_eta(token, %{"id" => claim_id, "status" => status})
       when status in @assigned or status in @picked_up do
    with {:ok, %{"route_points" => points}} <- Api.points_eta(token, claim_id),
         %{"visited_at" => %{"expected" => expected}} when is_binary(expected) <-
           points
           |> Enum.filter(&(&1["visit_status"] == "pending"))
           |> Enum.min_by(& &1["visit_order"], fn -> nil end) do
      %{"point_eta" => expected}
    else
      _other -> %{}
    end
  end

  defp point_eta(_token, _claim), do: %{}

  defp phone(token, %{"id" => claim_id} = claim) do
    with %{"id" => point_id} <- point(claim, "source"),
         {:ok, %{"phone" => phone} = response} <- Api.courier_phone(token, claim_id, point_id) do
      if response["ext"] in [nil, ""], do: phone, else: "#{phone},,#{response["ext"]}"
    else
      _other -> nil
    end
  end

  defp tracking_url(token, %{"id" => claim_id}) do
    with {:ok, %{"route_points" => points}} <- Api.tracking_links(token, claim_id),
         %{"sharing_link" => link} <- Enum.find(points, &(&1["type"] == "destination")) do
      link
    else
      _other -> nil
    end
  end

  defp point(%{"route_points" => points}, type) when is_list(points),
    do: Enum.find(points, &(&1["type"] == type))

  defp point(_claim, _type), do: nil

  defp performer(%{"courier_name" => name} = info) do
    car =
      Enum.reject([info["car_model"], info["car_color"], info["car_number"]], &(&1 in [nil, ""]))

    %{"name" => name, "car" => if(car != [], do: Enum.join(car, ", "))}
  end

  defp performer(_info), do: nil

  defp price(%{"final_price" => price}) when is_binary(price), do: price
  defp price(%{"offer" => %{"price" => price}}) when is_binary(price), do: price
  defp price(_pricing), do: nil

  defp configured(%Branch{info: %{yandex_delivery: %Settings{} = settings}}) do
    if Settings.configured?(settings), do: settings, else: {:error, :not_configured}
  end

  defp configured(_branch), do: {:error, :not_configured}

  defp switch_to_card(%Order{payment_method: :cash} = order) do
    with {:error, reason} <-
           Orders.update_payment_method(order, %{"payment_method" => "card_offline"}) do
      Logger.warning("order #{order.number}: cash to card switch failed (#{inspect(reason)})")
    end
  end

  defp switch_to_card(_order), do: :ok

  defp stale?(%Delivery{details: %{"synced_at" => synced_at}}) do
    case DateTime.from_iso8601(synced_at) do
      {:ok, at, _offset} -> DateTime.diff(DateTime.utc_now(), at) >= @stale_seconds
      _error -> true
    end
  end

  defp stale?(_delivery), do: true

  def active(branch_id) do
    Delivery
    |> where([d], d.branch_id == ^branch_id and d.provider == :yandex)
    |> where([d], d.status in ^Delivery.active() and not is_nil(d.external_id))
    |> Repo.all()
  end

  def active_branches do
    Delivery
    |> where([d], d.provider == :yandex and d.status in ^Delivery.active())
    |> distinct(true)
    |> select([d], d.branch_id)
    |> Repo.all()
  end
end
