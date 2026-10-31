defmodule Delivest.Couriers.Provider do
  alias Delivest.Couriers.Delivery
  alias Delivest.Oms.Order

  @callback key() :: atom()
  @callback name() :: String.t()
  @callback start(Delivery.t(), Order.t()) :: {:ok, map()} | {:error, term()}
  @callback cancel(Delivery.t()) :: :ok | {:error, term()}
  @callback health_check(settings :: struct()) :: :ok | {:error, term()}
  @callback classify_error(reason :: term()) :: Delivest.Integrations.Error.kind()

  @callback order_ready(Delivery.t()) :: :ok | {:error, term()}

  @optional_callbacks health_check: 1, classify_error: 1, order_ready: 1
end
