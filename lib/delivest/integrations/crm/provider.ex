defmodule Delivest.Integrations.Crm.Provider do
  alias Delivest.Oms.Order

  @type delivery :: %{
          required(:external_id) => String.t(),
          optional(:external_number) => String.t() | nil,
          optional(:warnings) => map()
        }

  @type error_kind :: :permanent | :retry | {:snooze, pos_integer()}

  @type catalog_item :: %{external_id: String.t(), name: String.t(), price: integer()}

  @type webhook_reply :: {:ok, map()} | {:error, :not_found | term()}

  @callback key() :: atom()
  @callback name() :: String.t()
  @callback settings_schema() :: module()
  @callback configured?(settings :: struct() | nil) :: boolean()

  @callback deliver_order(Order.t(), settings :: struct()) :: {:ok, delivery()} | {:error, term()}
  @callback classify_error(reason :: term()) :: error_kind()
  @callback rate_limit(settings :: struct()) ::
              {key :: term(), interval_ms :: pos_integer()} | nil

  @callback catalog_source(settings :: struct()) :: term()
  @callback fetch_catalog(settings :: struct()) :: {:ok, [catalog_item()]} | {:error, term()}

  @callback handle_webhook(token :: String.t(), params :: map()) :: webhook_reply()

  @optional_callbacks catalog_source: 1, fetch_catalog: 1, handle_webhook: 2
end
