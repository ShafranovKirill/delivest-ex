defmodule Delivest.Integrations.Yookassa.Webhook do
  @behaviour Delivest.Integrations.Inbox.Handler

  alias Delivest.Integrations.{Inbox, Yookassa}
  alias Delivest.Payments.Online

  @payment_events ~w(payment.waiting_for_capture payment.succeeded payment.canceled)
  @refund_events ~w(refund.succeeded)

  def handle(token, %{"event" => event, "object" => %{"id" => id}} = params)
      when event in @payment_events or event in @refund_events do
    if Yookassa.valid_webhook_token?(token) do
      {:ok, _accepted} =
        Inbox.accept(:yookassa, "#{event}:#{id}", nil, Map.take(params, ["event", "object"]))

      :ok
    else
      {:error, :invalid_token}
    end
  end

  def handle(token, _params) do
    if Yookassa.valid_webhook_token?(token), do: :ok, else: {:error, :invalid_token}
  end

  @impl true
  def handle_inbox(%{payload: %{"event" => event, "object" => %{"id" => id}}})
      when event in @payment_events do
    case Online.sync(id) do
      {:ok, _changed} -> :ok
      {:error, :payment_not_found} -> {:cancel, :payment_not_found}
      {:error, :amount_mismatch} -> {:cancel, :amount_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  def handle_inbox(%{payload: %{"event" => "refund.succeeded", "object" => %{"id" => id}}}) do
    case Online.sync_refund(id) do
      {:ok, _refund} -> :ok
      {:error, :refund_not_found} -> {:cancel, :refund_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def handle_inbox(_message), do: :ok
end
