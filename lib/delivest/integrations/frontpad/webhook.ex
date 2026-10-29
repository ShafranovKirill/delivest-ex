defmodule Delivest.Integrations.Frontpad.Webhook do
  @behaviour Delivest.Integrations.Inbox.Handler

  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.{Lookup, SyncState}
  alias Delivest.Integrations.{Inbox, Journal}

  @fields ~w(order_id status datetime)

  def handle(token, %{"action" => "change_status", "order_id" => order_id} = params) do
    with {:ok, info} <- Lookup.branch_info_by_webhook_token(:frontpad, token),
         event_id = Enum.join([order_id, params["status"], params["datetime"]], ":"),
         {:ok, _accepted} <-
           Inbox.accept(:frontpad, event_id, info.branch_id, Map.take(params, @fields)) do
      Journal.put_context(branch_id: info.branch_id)
      {:ok, %{result: "success"}}
    end
  end

  def handle(_token, _params), do: {:ok, %{result: "ignored"}}

  @impl true
  def handle_inbox(%{branch_id: branch_id, payload: payload}) do
    with {:ok, info} <- Lookup.branch_info(branch_id) do
      apply_status(info, payload["order_id"], payload["status"], payload["datetime"])
    end
  end

  def change_status(token, external_id, code, datetime) do
    with {:ok, info} <- Lookup.branch_info_by_webhook_token(:frontpad, token) do
      apply_status(info, external_id, code, datetime)
    end
  end

  defp apply_status(info, external_id, code, datetime) do
    with {:ok, order} <- Lookup.order_by_external_id(info.branch_id, :frontpad, external_id) do
      Journal.put_context(branch_id: order.branch_id, order_id: order.id)
      code = to_string(code)
      status = Crm.status_for(:frontpad, info.crm.frontpad, code)
      SyncState.remote_status(order, status, code, parse_datetime(datetime, order.branch_id))
    end
  end

  defp parse_datetime(datetime, branch_id) when is_binary(datetime) do
    with {:ok, naive} <- NaiveDateTime.from_iso8601(String.replace(datetime, " ", "T")),
         {:ok, local} <- DateTime.from_naive(naive, Delivest.LocalTime.timezone(branch_id)) do
      local |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:second)
    else
      _ -> DateTime.utc_now(:second)
    end
  end

  defp parse_datetime(_datetime, _branch_id), do: DateTime.utc_now(:second)
end
