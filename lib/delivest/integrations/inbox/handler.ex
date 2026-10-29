defmodule Delivest.Integrations.Inbox.Handler do
  alias Delivest.Integrations.Inbox.Message

  @callback handle_inbox(Message.t()) ::
              :ok | {:ok, term()} | {:error, term()} | {:cancel, term()}
end
