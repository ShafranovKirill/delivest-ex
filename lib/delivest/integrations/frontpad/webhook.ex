defmodule Delivest.Integrations.Frontpad.Webhook do
  import Ecto.Query, warn: false

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.SyncState
  alias Delivest.Integrations.Frontpad.StatusCodes
  alias Delivest.Oms.Order
  alias Delivest.Repo

  def change_status(token, external_id, code, datetime) do
    with {:ok, info} <- fetch_branch_info(token),
         {:ok, order} <- fetch_order(info.branch_id, to_string(external_id)) do
      code = to_string(code)
      status = StatusCodes.status_for(info.crm.frontpad.statuses, code)
      SyncState.remote_status(order, status, code, parse_datetime(datetime))
    end
  end

  defp fetch_branch_info(token) when is_binary(token) and token != "" do
    query =
      from(i in BranchInfo,
        where: fragment("?->'frontpad'->>'webhook_token' = ?", i.crm, ^token)
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      info -> {:ok, info}
    end
  end

  defp fetch_branch_info(_token), do: {:error, :not_found}

  defp fetch_order(branch_id, external_id) do
    query =
      from(o in Order,
        where: o.branch_id == ^branch_id and is_nil(o.deleted_at),
        where: fragment("?->>'provider' = 'frontpad'", o.crm),
        where: fragment("?->>'external_id' = ?", o.crm, ^external_id)
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      order -> {:ok, order}
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
