defmodule Delivest.Couriers.Provider do
  alias Delivest.Couriers.Delivery
  alias Delivest.Oms.Order

  @callback key() :: atom()
  @callback name() :: String.t()
  @callback start(Delivery.t(), Order.t()) :: {:ok, map()} | {:error, term()}
  @callback cancel(Delivery.t()) :: :ok | {:error, term()}
end
