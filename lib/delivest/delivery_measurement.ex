defmodule Delivest.DeliveryMeasurement do
  @moduledoc """
  Explicit delivery facts. No order deadline, cook_by, generic completion or
  provider polling time is inferred to be a customer promise or handover.

  Quality readers use initial_promised_delivery_at and delivered_at only.
  promised_delivery_at is the current customer-facing commitment.
  """
  import Ecto.Query

  alias Delivest.{Identity, Repo}
  alias Delivest.Couriers.Delivery
  alias Delivest.Identity.Staff
  alias Delivest.Oms.Order
  alias Delivest.Oms.Orders.Notifier
  alias Delivest.DeliveryMeasurement.{ActualEvent, PromiseHistory}

  @promise_statuses [:accepted, :preparing, :ready]
  @provider_sources [:yandex_delivery]

  def confirm_promise(staff, branch_id, order_id, promised_at, reason \\ nil)

  def confirm_promise(
        %Staff{} = staff,
        branch_id,
        order_id,
        %DateTime{} = promised_at,
        reason
      ) do
    with :ok <- Identity.authorize(staff, "orders.update", branch_id),
         :ok <- utc?(promised_at) do
      Repo.transaction(fn ->
        order = lock_order!(order_id)
        assert_branch!(order, branch_id)

        unless order.fulfillment_type == :delivery and order.status in @promise_statuses,
          do: Repo.rollback(:not_eligible)

        if order.promised_delivery_at &&
             DateTime.compare(order.promised_delivery_at, promised_at) == :eq do
          order
        else
          initial? = is_nil(order.initial_promised_delivery_at)
          reason = if is_binary(reason), do: String.trim(reason), else: ""

          if not initial? and reason == "", do: Repo.rollback(:reason_required)

          if DateTime.compare(promised_at, DateTime.utc_now()) == :lt,
            do: Repo.rollback(:past_promise)

          now = DateTime.utc_now()

          {:ok, _} =
            Repo.insert(%PromiseHistory{
              order_id: order.id,
              staff_id: staff.id,
              source: "staff",
              promised_at: promised_at,
              reason: if(initial?, do: nil, else: reason),
              recorded_at: now
            })

          attrs = %{promised_delivery_at: promised_at}

          attrs =
            if initial?,
              do: Map.put(attrs, :initial_promised_delivery_at, promised_at),
              else: attrs

          {:ok, updated} = order |> Ecto.Changeset.change(attrs) |> Repo.update()
          updated
        end
      end)
      |> unwrap()
      |> then(&Notifier.publish(&1, [:order, :updated]))
    end
  end

  def confirm_promise(_, _, _, _, _), do: {:error, :invalid_promise}

  # Called only inside the successful courier status transaction. Never called
  # for a generic order completion or a provider status sync.
  def record_handover(repo, %Order{} = order, steps, {:courier, %Staff{id: courier_id}})
      when is_list(steps) do
    if Enum.any?(steps, fn {from, to} -> from == :delivering and to == :completed end) do
      delivery =
        repo.one(
          from d in Delivery,
            where:
              d.order_id == ^order.id and d.provider == :staff and d.status == :picked_up and
                d.courier_id == ^courier_id,
            lock: "FOR UPDATE"
        )

      if delivery do
        # A delivery ID is stable across retries; no newly generated dedupe key.
        source = "staff_handover"
        event_id = "staff_handover:#{delivery.id}"
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        if is_nil(repo.get_by(ActualEvent, source: source, event_id: event_id)) do
          {:ok, _} =
            repo.insert(%ActualEvent{
              order_id: order.id,
              event_id: event_id,
              source: source,
              occurred_at: now,
              received_at: now
            })
        end

        if is_nil(order.delivered_at) do
          order
          |> Ecto.Changeset.change(%{
            delivered_at: now,
            delivery_actual_received_at: now,
            delivery_actual_source: source
          })
          |> repo.update()
        else
          {:ok, order}
        end
      else
        {:error, :handover_without_delivery}
      end
    else
      {:ok, order}
    end
  end

  def record_handover(_repo, order, _steps, _by), do: {:ok, order}

  @doc """
  Trusted ingestion entry point, for a future provider adapter which actually
  supplies a verified occurred_at (not an ETA or webhook receipt time).
  event_id is the provider's stable delivery event identifier.
  """
  def record_provider_actual(order_id, source, event_id, %DateTime{} = occurred_at)
      when source in @provider_sources and is_binary(event_id) and byte_size(event_id) > 0 do
    occurred_at = DateTime.truncate(occurred_at, :second)

    with :ok <- utc?(occurred_at),
         :ok <- plausible_actual?(occurred_at) do
      Repo.transaction(fn ->
        order = lock_order!(order_id)

        unless match?(%Order{}, order),
          do: Repo.rollback(:not_found)

        unless order.fulfillment_type == :delivery and order.status == :completed and
                 DateTime.compare(occurred_at, order.inserted_at) != :lt and
                 Repo.exists?(
                   from d in Delivery,
                     where:
                       d.order_id == ^order.id and d.provider == :yandex and
                         not is_nil(d.external_id) and
                         (d.status == :delivered or
                            (d.status == :picked_up and
                               fragment("?->>'status' = 'delivered_finish'", d.details)))
                 ),
               do: Repo.rollback(:not_eligible)

        source_name = Atom.to_string(source)
        existing = Repo.get_by(ActualEvent, source: source_name, event_id: event_id)

        cond do
          existing && existing.order_id != order.id ->
            Repo.rollback(:event_conflict)

          existing && DateTime.compare(existing.occurred_at, occurred_at) != :eq ->
            Repo.rollback(:event_conflict)

          existing ->
            order

          true ->
            now = DateTime.utc_now() |> DateTime.truncate(:second)

            {:ok, _} =
              Repo.insert(%ActualEvent{
                order_id: order.id,
                source: source_name,
                event_id: event_id,
                occurred_at: occurred_at,
                received_at: now
              })

            if is_nil(order.delivered_at) do
              {:ok, updated} =
                order
                |> Ecto.Changeset.change(%{
                  delivered_at: occurred_at,
                  delivery_actual_received_at: now,
                  delivery_actual_source: source_name
                })
                |> Repo.update()

              updated
            else
              order
            end
        end
      end)
      |> unwrap()
    end
  end

  def record_provider_actual(_, _, _, _), do: {:error, :invalid_event}

  def history(order_id),
    do:
      Repo.all(
        from h in PromiseHistory,
          where: h.order_id == ^order_id,
          order_by: [asc: h.recorded_at, asc: h.id]
      )

  defp lock_order!(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        Repo.one(
          from o in Order, where: o.id == ^uuid and is_nil(o.deleted_at), lock: "FOR UPDATE"
        )

      :error ->
        nil
    end
  end

  defp assert_branch!(%Order{branch_id: branch_id}, branch_id), do: :ok
  defp assert_branch!(_, _), do: Repo.rollback(:not_found)

  defp utc?(%DateTime{time_zone: "Etc/UTC"}), do: :ok
  defp utc?(_), do: {:error, :invalid_timestamp}

  defp plausible_actual?(at) do
    if DateTime.compare(at, DateTime.add(DateTime.utc_now(), 60, :second)) == :gt,
      do: {:error, :future_event},
      else: :ok
  end

  defp unwrap({:ok, value}), do: {:ok, value}
  defp unwrap({:error, reason}), do: {:error, reason}
end
