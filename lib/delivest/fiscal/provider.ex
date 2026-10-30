defmodule Delivest.Fiscal.Provider do
  alias Delivest.Fiscal.Receipt

  @type result :: %{
          required(:status) => :wait | :done | :fail,
          optional(:uuid) => String.t(),
          optional(:payload) => map(),
          optional(:error) => String.t()
        }

  @callback key() :: atom()
  @callback name() :: String.t()
  @callback body(Receipt.t(), receipt :: map(), settings :: struct()) :: map()
  @callback register(Receipt.t(), body :: map(), settings :: struct()) ::
              {:ok, result()} | {:error, term()}
  @callback fetch(Receipt.t(), settings :: struct()) :: {:ok, result()} | {:error, term()}
  @callback classify_error(reason :: term()) :: Delivest.Integrations.Error.kind()
  @callback callback_token(settings :: struct()) :: String.t() | nil
  @callback parse_callback(params :: map()) :: {:ok, String.t(), result()} | {:error, term()}
  @callback health_check(settings :: struct()) :: :ok | {:error, term()}
end
