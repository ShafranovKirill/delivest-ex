defmodule Delivest.Integrations.Crm.Provider do
  alias Delivest.Oms.Order

  @type delivery :: %{
          required(:external_id) => String.t(),
          optional(:external_number) => String.t() | nil,
          optional(:warnings) => map()
        }

  @type error_kind :: :permanent | :retry | {:snooze, pos_integer()}

  @callback name() :: String.t()
  @callback deliver_order(Order.t(), settings :: struct()) :: {:ok, delivery()} | {:error, term()}
  @callback classify_error(reason :: term()) :: error_kind()
  @callback rate_limit(settings :: struct()) ::
              {key :: term(), interval_ms :: pos_integer()} | nil

  @type catalog_item :: %{external_id: String.t(), name: String.t(), price: integer()}

  @callback catalog_source(settings :: struct()) :: term()
  @callback fetch_catalog(settings :: struct()) :: {:ok, [catalog_item()]} | {:error, term()}

  @optional_callbacks catalog_source: 1, fetch_catalog: 1
end
