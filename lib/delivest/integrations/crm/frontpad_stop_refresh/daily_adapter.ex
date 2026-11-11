defmodule Delivest.Integrations.Crm.FrontpadStopRefresh.DailyAdapter do
  @moduledoc "Dispatches the daily Frontpad refresh without waiting for the provider."

  alias Delivest.Integrations.Crm.FrontpadStopRefresh

  def perform(%Oban.Job{args: %{"scope_id" => branch_id}}) do
    case FrontpadStopRefresh.request_internal(branch_id, :daily) do
      {:ok, _result} -> :ok
      error -> error
    end
  end
end
