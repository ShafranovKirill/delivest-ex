defmodule Delivest.Events.Subscriber do
  alias Delivest.Events.Event

  @callback key() :: atom()
  @callback events() :: [String.t()]
  @callback handle(Event.t()) :: :ok | {:ok, term()} | {:error, term()} | {:cancel, term()}

  @doc """
  Optional best-effort UI notification after the delivery transaction commits.
  This callback must not perform business mutations; failures cannot retry the committed delivery.
  """
  @callback after_commit(Event.t()) :: :ok
  @optional_callbacks after_commit: 1
end
