defmodule Delivest.Integrations.Crm.Provider do
  alias Delivest.Oms.Order

  @callback name() :: String.t()
  @callback deliver_order(Order.t(), settings :: struct()) ::
              {:ok, external_id :: String.t()} | {:error, term()}
  @callback permanent_error?(reason :: term()) :: boolean()
end
