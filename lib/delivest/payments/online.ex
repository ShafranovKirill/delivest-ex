defmodule Delivest.Payments.Online do
  import Ecto.Query

  require Logger

  alias Delivest.Integrations.Yookassa
  alias Delivest.Integrations.Yookassa.Api
  alias Delivest.Oms.{Order, OrderEvents, Orders}
  alias Delivest.Oms.Orders.Notifier
  alias Delivest.Payments
  alias Delivest.Payments.Payment
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
      with %Payment{} = payment <- locked(id),
           :ok <- check_amount(payment, remote),
           %Order{} = order <- Repo.get!(Order, payment.order_id),
           {:ok, changed} <- move(order, payment, status) do
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

  defp move(order, %Payment{status: :pending} = payment, "waiting_for_capture") do
    with {:ok, _payment} <- Payments.advance(Repo, order, payment, :authorized, :system),
         {:ok, _order} <- release(order) do
      {:ok, :authorized}
    end
  end

  defp move(order, %Payment{status: status} = payment, "succeeded")
       when status in [:pending, :authorized] do
    with {:ok, _payment} <-
           Payments.advance(Repo, order, payment, :paid, :system, %{
             paid_at: DateTime.utc_now(:second)
           }),
         {:ok, _order} <- release(order) do
      {:ok, :paid}
    end
  end

  defp move(order, %Payment{status: status} = payment, "canceled")
       when status in [:pending, :authorized] do
    with {:ok, _payment} <- Payments.advance(Repo, order, payment, :cancelled, :system) do
      {:ok, if(order.awaiting_payment, do: :abandoned, else: :cancelled)}
    end
  end

  defp move(_order, _payment, _status), do: {:ok, :unchanged}

  defp release(%Order{awaiting_payment: true} = order) do
    with {:ok, order} <- order |> Ecto.Changeset.change(awaiting_payment: false) |> Repo.update(),
         {:ok, _event} <- OrderEvents.created(Repo, order, :system) do
      {:ok, order}
    end
  end

  defp release(order), do: {:ok, order}

  defp publish(order, :abandoned), do: abandon(Repo.get!(Order, order.id))

  defp publish(order, changed) when changed in [:authorized, :paid],
    do: Notifier.publish({:ok, Repo.get!(Order, order.id)}, [:order, :created])

  defp publish(_order, _changed), do: :ok

  defp check_amount(payment, remote) do
    expected = get_in(payment.details, ["hold_amount"]) || payment.amount

    case Api.parse_amount(remote["amount"]) do
      {:ok, ^expected} ->
        :ok

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

  defp create(order, payment) do
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

  defp return_url(order),
    do: Application.fetch_env!(:delivest, :client_origin) <> "/orders?order=" <> order.id

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
