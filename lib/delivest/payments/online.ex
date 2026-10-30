defmodule Delivest.Payments.Online do
  import Ecto.Query

  alias Delivest.Integrations.Yookassa
  alias Delivest.Integrations.Yookassa.Api
  alias Delivest.Oms.{Order, Orders}
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

  defp create(order, payment) do
    settings = Yookassa.get_settings()

    with {:ok, body} <- Api.create_payment(settings, payment.id, body(order, payment)),
         {:ok, id, url} <- confirmation(body),
         {:ok, _payment} <-
           payment
           |> Payment.link_changeset(id, %{"confirmation_url" => url})
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
