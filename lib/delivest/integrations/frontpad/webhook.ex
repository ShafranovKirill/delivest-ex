defmodule Delivest.Integrations.Frontpad.Webhook do
  alias Delivest.Integrations.Crm.{Lookup, SyncState}
  alias Delivest.Integrations.Journal
  alias Delivest.Integrations.Frontpad.StatusCodes

  def handle(token, %{"action" => "change_status", "order_id" => order_id} = params) do
    with {:ok, _order} <- change_status(token, order_id, params["status"], params["datetime"]) do
      {:ok, %{result: "success"}}
    end
  end

  def handle(_token, _params), do: {:ok, %{result: "ignored"}}

  def change_status(token, external_id, code, datetime) do
    with {:ok, info} <- Lookup.branch_info_by_webhook_token(:frontpad, token),
         {:ok, order} <- Lookup.order_by_external_id(info.branch_id, :frontpad, external_id) do
      Journal.put_context(branch_id: order.branch_id, order_id: order.id)
      code = to_string(code)
      status = StatusCodes.status_for(info.crm.frontpad.statuses, code)
      SyncState.remote_status(order, status, code, parse_datetime(datetime))
    end
  end

  defp parse_datetime(datetime) when is_binary(datetime) do
    with {:ok, naive} <- NaiveDateTime.from_iso8601(String.replace(datetime, " ", "T")),
         {:ok, local} <- DateTime.from_naive(naive, Delivest.LocalTime.timezone()) do
      local |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:second)
    else
      _ -> DateTime.utc_now(:second)
    end
  end

  defp parse_datetime(_datetime), do: DateTime.utc_now(:second)
end
