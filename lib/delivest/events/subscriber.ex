defmodule Delivest.Events.Subscriber do
  alias Delivest.Events.Event

  @callback key() :: atom()
  @callback events() :: [String.t()]
  @callback handle(Event.t()) :: :ok | {:ok, term()} | {:error, term()} | {:cancel, term()}
end
