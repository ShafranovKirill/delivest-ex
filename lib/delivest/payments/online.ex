defmodule Delivest.Payments.Online do
  import Ecto.Query

  require Logger

  alias Delivest.Integrations.Yookassa
  alias Delivest.Integrations.Yookassa.Api
  alias Delivest.Fiscal
  alias Delivest.Identity.Branch
  alias Delivest.Oms.{Order, OrderEvents, OrderFlow, Orders}
  alias Delivest.Oms.Orders.Notifier
  alias Delivest.Payments
  alias Delivest.Payments.{Payment, Refund}
  alias Delivest.Repo

  def start(%Order{awaiting_payment: true} = order) do
    with %Payment{} = payment <- pending(order.id) do
      case payment.details do
        %{"confirmation_url" => url} when is_binary(url) -> {:ok, url}
        _details -> create(order, payment)
      end
    else
      nil -> {:error, :no_payment}
    end
  end

  def start(%Order{}), do: {:error, :not_awaiting}

  def abandon(%Order{} = order) do
    Orders.advance_order(order, :cancelled, :system, attrs: %{cancel_reason: :not_paid})
  end

  def sync(external_id) when is_binary(external_id) do
    with {:ok, remote} <- Api.get_payment(Yookassa.get_settings(), external_id) do
      apply_remote(remote)
    end
  end

  def apply_remote(%{"id" => id, "status" => status} = remote) when is_binary(id) do
    Repo.transaction(fn ->
      with %Payment{} = found <- Repo.get_by(Payment, provider: "yookassa", external_id: id),
           %Order{} = order <- locked_order(found.order_id),
           %Payment{} = payment <- locked(id),
           {:ok, amount} <- check_amount(payment, remote),
           {:ok, changed} <- move(order, payment, status, amount) do
        {order, changed}
      else
        nil -> Repo.rollback(:payment_not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {order, changed}} ->
        publish(order, changed)
        {:ok, changed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def apply_remote(_remote), do: {:error, :bad_response}

  def send_refund(%Refund{payment: %Payment{external_id: payment_id}} = refund)
      when is_binary(payment_id) do
    body = %{
      payment_id: payment_id,
      amount: Api.amount(refund.amount),
      description: refund.reason
    }

    body =
      if refund.provider == "yookassa",
        do: Map.put(body, :metadata, %{refund_id: refund.id}),
        else: body

    with {:ok, remote} <- fetch_or_create_refund(refund, body),
         {:ok, _refund} <- apply_refund(refund, remote) do
      :ok
    end
  end

  def send_refund(_refund), do: {:cancel, :no_payment}

  def sync_refund(external_id) when is_binary(external_id) do
    with {:ok, remote} <- Api.get_refund(Yookassa.get_settings(), external_id) do
      case Repo.get_by(Refund, provider: "yookassa", external_id: external_id) do
        %Refund{} = refund -> apply_refund(refund, remote)
        nil -> {:error, :refund_not_found}
      end
    end
  end

  defp fetch_or_create_refund(%Refund{external_id: id}, _body) when is_binary(id),
    do: Api.get_refund(Yookassa.get_settings(), id)

  defp fetch_or_create_refund(refund, body) do
    if DateTime.diff(DateTime.utc_now(), refund.inserted_at, :second) < 86_400 do
      Api.create_refund(Yookassa.get_settings(), refund.id, body)
    else
      if refund.provider == "yookassa",
        do: reconcile_refund(refund, body.payment_id, nil, MapSet.new()),
        else: {:error, :refund_outcome_unknown}
    end
  end

  defp reconcile_refund(refund, payment_id, cursor, seen) do
    params =
      if cursor, do: [payment_id: payment_id, cursor: cursor], else: [payment_id: payment_id]

    with {:ok, %{"items" => items} = page} <- Api.list_refunds(Yookassa.get_settings(), params) do
      case Enum.find(items, &(get_in(&1, ["metadata", "refund_id"]) == refund.id)) do
        nil ->
          case page["next_cursor"] do
            cursor when is_binary(cursor) ->
              cond do
                MapSet.member?(seen, cursor) -> {:error, :refund_cursor_cycle}
                MapSet.size(seen) >= 49 -> {:error, :refund_scan_incomplete}
                true -> reconcile_refund(refund, payment_id, cursor, MapSet.put(seen, cursor))
              end

            _ ->
              {:error, :refund_outcome_unknown}
          end

        remote ->
          {:ok, remote}
      end
    end
  end

  defp apply_refund(
         %Refund{} = refund,
         %{"id" => id, "status" => status} = remote
       )
       when is_binary(id) and status in ["pending", "succeeded", "canceled"] do
    Repo.transaction(fn ->
      _order = locked_order(refund.order_id) || Repo.rollback(:order_not_found)

      _payment =
        Repo.one!(from(p in Payment, where: p.id == ^refund.payment_id, lock: "FOR UPDATE"))

      locked = Repo.one!(from(r in Refund, where: r.id == ^refund.id, lock: "FOR UPDATE"))

      with :ok <- check_refund_identity(locked, remote),
           {:ok, changed} <- move_refund(locked, id, status) do
        changed
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp apply_refund(_refund, _remote), do: {:error, :bad_response}

  defp move_refund(%Refund{status: status} = refund, _id, _remote_status)
       when status != :pending,
       do: {:ok, refund}

  defp move_refund(refund, id, "succeeded") do
    with {:ok, refund} <-
           refund
           |> Refund.move_changeset(:succeeded, %{
             external_id: id,
             refunded_at: DateTime.utc_now(:second)
           })
           |> Ecto.Changeset.put_change(:provider, "yookassa")
           |> Repo.update(),
         :ok <- Fiscal.enqueue_online_refund(refund) do
      {:ok, refund}
    end
  end

  defp move_refund(refund, id, "canceled") do
    refund
    |> Refund.move_changeset(:failed, %{external_id: id})
    |> Ecto.Changeset.put_change(:provider, "yookassa")
    |> Repo.update()
  end

  defp move_refund(refund, id, "pending") do
    refund
    |> Ecto.Changeset.change(external_id: id, provider: "yookassa")
    |> Ecto.Changeset.force_change(:updated_at, DateTime.utc_now(:second))
    |> Repo.update()
  end

  defp check_refund_identity(refund, remote) do
    payment = Repo.get!(Payment, refund.payment_id)

    cond do
      refund.external_id && refund.external_id != remote["id"] ->
        {:error, :refund_id_mismatch}

      remote["payment_id"] != payment.external_id ->
        {:error, :payment_mismatch}

      Api.parse_amount(remote["amount"]) != {:ok, refund.amount} ->
        {:error, :amount_mismatch}

      true ->
        :ok
    end
  end

  def capture(%Order{} = order, %Payment{status: :authorized, external_id: id} = payment)
      when is_binary(id) do
    settings = Yookassa.get_settings()

    case Api.capture(settings, key(payment, "capture"), id, payment.amount) do
      {:ok, remote} ->
        finish_capture(order, id, remote)

      {:error, reason} ->
        case Api.get_payment(settings, id) do
          {:ok, %{"status" => "succeeded"} = remote} -> finish_capture(order, id, remote)
          _ -> {:error, reason}
        end
    end
  end

  def capture(_order, _payment), do: :ok

  defp finish_capture(order, id, %{"id" => id, "status" => "succeeded"} = remote) do
    with {:ok, _changed} <- apply_remote(remote) do
      Logger.info("yookassa payment #{id} of order #{order.number} was captured")
      :ok
    end
  end

  defp finish_capture(_order, _id, _remote), do: {:error, :capture_not_confirmed}

  def release(%Payment{external_id: id, details: details} = payment) when is_binary(id) do
    if details["released"] do
      :ok
    else
      with {:ok, remote} <- Api.get_payment(Yookassa.get_settings(), id) do
        if remote["status"] == "succeeded",
          do: apply_remote(remote) |> release_result(),
          else: release(payment, remote["status"])
      end
    end
  end

  def release(_payment), do: :ok

  defp release(payment, "waiting_for_capture") do
    with {:ok, _remote} <-
           Api.cancel(Yookassa.get_settings(), key(payment, "cancel"), payment.external_id) do
      mark_released(payment)
    end
  end

  defp release(payment, "canceled"), do: mark_released(payment)
  defp release(_payment, "pending"), do: :ok

  defp release(payment, status) do
    Logger.error(
      "yookassa payment #{payment.external_id} is #{status} but the order was cancelled, refund it"
    )

    :ok
  end

  defp release_result({:ok, _changed}), do: :ok
  defp release_result(error), do: error

  defp mark_released(payment) do
    with {:ok, _payment} <-
           payment
           |> Payment.link_changeset(payment.external_id, %{"released" => true})
           |> Repo.update() do
      :ok
    end
  end

  defp key(%Payment{id: id}, action), do: id <> ":" <> action

  defp move(order, %Payment{status: :pending} = payment, "waiting_for_capture", _amount) do
    with {:ok, _payment} <- Payments.advance(Repo, order, payment, :authorized, :system),
         {:ok, _order} <- open_to_work(order) do
      {:ok, :authorized}
    end
  end

  defp move(
         %Order{status: :cancelled} = order,
         %Payment{status: status} = payment,
         "succeeded",
         amount
       )
       when status in [:pending, :authorized, :cancelled, :paid] do
    with {:ok, payment} <- record_capture(order, payment, amount),
         {:ok, _refund} <- refund_cancelled(payment) do
      {:ok, :refunded_paid}
    end
  end

  defp move(order, %Payment{status: status} = payment, "succeeded", amount)
       when status in [:pending, :authorized] do
    with {:ok, payment} <- payment |> Ecto.Changeset.change(amount: amount) |> Repo.update(),
         {:ok, _payment} <-
           Payments.advance(Repo, order, payment, :paid, :system, %{
             paid_at: DateTime.utc_now(:second),
             fiscalized_by: if(order.crm, do: :crm)
           }),
         {:ok, _order} <- open_to_work(order) do
      {:ok, :paid}
    end
  end

  defp move(order, %Payment{status: status} = payment, "canceled", _amount)
       when status in [:pending, :authorized] do
    with {:ok, _payment} <- Payments.advance(Repo, order, payment, :cancelled, :system) do
      {:ok, if(order.awaiting_payment, do: :abandoned, else: :cancelled)}
    end
  end

  defp move(_order, %Payment{status: status} = payment, "waiting_for_capture", _amount)
       when status in [:cancelled, :failed],
       do: {:ok, {:late_hold, payment}}

  defp move(_order, _payment, _status, _amount), do: {:ok, :unchanged}

  defp record_capture(_order, %Payment{status: :paid} = payment, amount) do
    if payment.amount == amount,
      do: {:ok, payment},
      else: {:error, :amount_mismatch}
  end

  defp record_capture(order, payment, amount) do
    with {:ok, payment} <- payment |> Ecto.Changeset.change(amount: amount) |> Repo.update(),
         {:ok, payment} <-
           Payments.advance(Repo, order, payment, :paid, :system, %{
             paid_at: DateTime.utc_now(:second),
             fiscalized_by: if(order.crm, do: :crm)
           }) do
      {:ok, payment}
    end
  end

  defp refund_cancelled(payment) do
    case Payments.refund_left(payment) do
      left when left > 0 -> Payments.refund(payment, left, %{reason: "order cancelled"})
      _ -> {:ok, nil}
    end
  end

  defp open_to_work(%Order{awaiting_payment: true} = order) do
    with {:ok, order} <- order |> Ecto.Changeset.change(awaiting_payment: false) |> Repo.update(),
         {:ok, _event} <- OrderEvents.created(Repo, order, :system) do
      {:ok, order}
    end
  end

  defp open_to_work(order), do: {:ok, order}

  defp publish(order, :abandoned), do: abandon(Repo.get!(Order, order.id))

  defp publish(order, :cancelled) do
    order = Repo.get!(Order, order.id)
    if OrderFlow.active?(order), do: abandon(order), else: :ok
  end

  defp publish(order, changed) when changed in [:authorized, :paid] do
    order = Repo.get!(Order, order.id)
    Notifier.publish({:ok, order}, [:order, :created])
    if changed == :authorized and auto_accept?(order), do: accept(order), else: :ok
  end

  defp publish(_order, {:late_hold, payment}), do: release(payment)

  defp publish(_order, _changed), do: :ok

  defp accept(order), do: Orders.advance_order(order, :accepted, :system)

  defp auto_accept?(%Order{} = order) do
    %Branch{id: order.branch_id} |> Payments.settings() |> Map.fetch!(:skip_confirmation_call)
  end

  defp check_amount(payment, remote) do
    expected =
      if remote["status"] == "succeeded",
        do: payment.amount,
        else: get_in(payment.details, ["hold_amount"]) || payment.amount

    case Api.parse_amount(remote["amount"]) do
      {:ok, amount} when amount > 0 ->
        if remote["status"] == "succeeded" do
          if amount != expected,
            do:
              Logger.warning(
                "yookassa payment #{payment.external_id} captured #{amount}, expected #{expected}"
              )

          {:ok, amount}
        else
          if amount == expected, do: {:ok, amount}, else: {:error, :amount_mismatch}
        end

      other ->
        Logger.error(
          "yookassa payment #{payment.external_id} has amount #{inspect(other)}, expected #{expected}"
        )

        {:error, :amount_mismatch}
    end
  end

  defp locked(external_id) do
    Repo.one(
      from(p in Payment,
        where: p.provider == "yookassa" and p.external_id == ^external_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp locked_order(order_id) do
    Repo.one(from(o in Order, where: o.id == ^order_id, lock: "FOR UPDATE"))
  end

  defp create(order, payment) do
    if Yookassa.ready?(), do: create_enabled(order, payment), else: {:error, :online_unavailable}
  end

  defp create_enabled(order, payment) do
    settings = Yookassa.get_settings()

    with {:ok, body} <- Api.create_payment(settings, payment.id, body(order, payment)),
         {:ok, id, url} <- confirmation(body),
         {:ok, _payment} <-
           payment
           |> Payment.link_changeset(id, %{
             "confirmation_url" => url,
             "hold_amount" => payment.amount
           })
           |> Repo.update() do
      {:ok, url}
    else
      {:error, reason} -> {:error, reason}
      :error -> {:error, :bad_response}
    end
  end

  defp body(order, payment) do
    %{
      amount: Api.amount(payment.amount),
      capture: false,
      confirmation: %{type: "redirect", return_url: return_url(order)},
      description: "Заказ #{Order.short_number(order)}",
      metadata: %{order_id: order.id, payment_id: payment.id}
    }
  end

  defp confirmation(%{"id" => id, "confirmation" => %{"confirmation_url" => url}})
       when is_binary(id) and is_binary(url),
       do: {:ok, id, url}

  defp confirmation(_body), do: :error

  defp return_url(order) do
    slug = Repo.one(from(b in Branch, where: b.id == ^order.branch_id, select: b.slug))
    Application.fetch_env!(:delivest, :client_origin) <> "/#{slug}?order=" <> order.id
  end

  defp pending(order_id) do
    Repo.one(
      from(p in Payment,
        where: p.order_id == ^order_id and p.method == :online and p.status == :pending,
        order_by: [desc: p.inserted_at],
        limit: 1
      )
    )
  end
end
