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
end
