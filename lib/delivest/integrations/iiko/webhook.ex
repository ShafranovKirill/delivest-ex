defmodule Delivest.Integrations.Iiko.Webhook do
  @behaviour Delivest.Integrations.Inbox.Handler

  require Logger

  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.{Lookup, StopSync, SyncState}
  alias Delivest.Integrations.Iiko.Api
  alias Delivest.Integrations.{Inbox, Journal}
  alias Delivest.Oms.{Order, Orders}

  @order_events ~w(DeliveryOrderUpdate DeliveryOrderError)

  def handle(token, params) do
    with {:ok, info} <- Lookup.branch_info_by_webhook_token(:iiko, token) do
      Journal.put_context(branch_id: info.branch_id)
      params |> events() |> Enum.each(&accept(info, &1))
      {:ok, %{result: "success"}}
    end
  end

  defp events(%{"_json" => events}) when is_list(events), do: events
  defp events(events) when is_list(events), do: events
  defp events(%{"eventType" => _type} = event), do: [event]
  defp events(_params), do: []

  defp accept(info, %{"eventType" => type, "eventInfo" => %{"id" => id}} = event)
       when type in @order_events do
    event_id = Enum.join([type, id, event["correlationId"], event["eventTime"]], ":")
    payload = %{"type" => type, "order_id" => id, "error" => error(event["eventInfo"])}
    Inbox.accept(:iiko, event_id, info.branch_id, payload)
  end

  defp accept(info, %{"eventType" => "StopListUpdate"}) do
    Task.start(fn -> StopSync.sync(info.branch_id) end)
  end

  defp accept(_info, _event), do: :ok

  @impl true
  def handle_inbox(%{branch_id: branch_id, payload: %{"order_id" => order_id} = payload}) do
    with %Order{branch_id: ^branch_id, crm: %{provider: "iiko"}} = order <-
           Orders.get_order(order_id) || {:error, :not_found},
         {:ok, info} <- Lookup.branch_info(branch_id) do
      Journal.put_context(branch_id: branch_id, order_id: order.id)
      refresh(order, info.crm.iiko, payload)
    else
      %Order{} -> {:error, :not_found}
      error -> error
    end
  end

  def refresh(order, settings, payload \\ %{}) do
    case Api.deliveries(settings, [order.id]) do
      {:ok, %{"orders" => [remote | _]}} -> apply_remote(order, remote, payload)
      {:ok, _body} -> {:error, :not_found}
      error -> error
    end
  end

  defp apply_remote(order, %{"creationStatus" => "Error"} = remote, payload) do
    error = error(remote) || payload["error"] || "iiko error"

    case Crm.reject_order(order, error) do
      {:error, :not_confirming} -> :ok
      result -> result
    end
  end

  defp apply_remote(order, %{"creationStatus" => "Success", "order" => remote}, _payload) do
    order =
      case Crm.confirm_order(order, %{external_id: order.id, external_number: number(remote)}) do
        {:ok, %Order{} = confirmed} -> confirmed
        _not_confirming -> order
      end

    status(order, remote["status"])
  end

  defp apply_remote(_order, _remote, _payload), do: :ok

  defp status(_order, nil), do: :ok

  defp status(%Order{crm: %{remote_status_code: code}}, code), do: :ok

  defp status(order, code) do
    status = Crm.status_for(:iiko, nil, code)
    SyncState.remote_status(order, status, code, DateTime.utc_now(:second))
  end

  defp number(%{"number" => number}) when not is_nil(number), do: to_string(number)
  defp number(_remote), do: nil

  defp error(%{"errorInfo" => %{"message" => message}}) when is_binary(message), do: message

  defp error(%{"errorInfo" => %{"description" => text}}) when is_binary(text), do: text
  defp error(_info), do: nil
end
