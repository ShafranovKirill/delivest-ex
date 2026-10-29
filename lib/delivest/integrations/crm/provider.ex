defmodule Delivest.Integrations.Crm.Provider do
  alias Delivest.Oms.Order

  @type delivery :: %{
          required(:external_id) => String.t(),
          optional(:external_number) => String.t() | nil,
          optional(:warnings) => map()
        }

  @type error_kind :: Delivest.Integrations.Error.kind()

  @type catalog_item :: %{external_id: String.t(), name: String.t(), price: integer()}

  @type capability ::
          :cancel
          | :update_items
          | :update_comment
          | :update_address
          | :update_time
          | :update_payments

  @type dictionary :: %{optional(atom()) => [%{id: String.t(), name: String.t()}]}

  @type webhook_reply :: {:ok, map()} | {:error, :not_found | term()}

  @callback key() :: atom()
  @callback name() :: String.t()
  @callback settings_schema() :: module()
  @callback configured?(settings :: struct() | nil) :: boolean()

  @callback deliver_order(Order.t(), settings :: struct()) ::
              {:ok, delivery()} | {:pending, ref :: String.t()} | {:error, term()}
  @callback idempotent?() :: boolean()
  @callback capabilities() :: [capability()]
  @callback cancel_order(Order.t(), reason :: atom() | nil, settings :: struct()) ::
              :ok | {:error, term()}
  @callback update_order(Order.t(), changes :: map(), settings :: struct()) ::
              :ok | {:pending, ref :: String.t()} | {:error, term()}
  @callback status_map(settings :: struct()) :: %{String.t() => atom()}
  @callback dictionaries(settings :: struct()) :: {:ok, dictionary()} | {:error, term()}
  @callback classify_error(reason :: term()) :: error_kind()
  @callback health_check(settings :: struct() | nil) :: :ok | {:error, term()}
  @callback rate_limit(settings :: struct()) ::
              {key :: term(), interval_ms :: pos_integer()} | nil

  @callback catalog_source(settings :: struct()) :: term()
  @callback fetch_catalog(settings :: struct()) :: {:ok, [catalog_item()]} | {:error, term()}

  @callback handle_webhook(token :: String.t(), params :: map()) :: webhook_reply()

  @callback stops_enabled?(settings :: struct()) :: boolean()
  @callback fetch_stops(settings :: struct()) :: {:ok, [String.t()]} | {:error, term()}

  @optional_callbacks idempotent?: 0,
                      capabilities: 0,
                      cancel_order: 3,
                      update_order: 3,
                      status_map: 1,
                      dictionaries: 1,
                      catalog_source: 1,
                      fetch_catalog: 1,
                      handle_webhook: 2,
                      stops_enabled?: 1,
                      fetch_stops: 1
end
