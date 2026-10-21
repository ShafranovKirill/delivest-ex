defmodule DelivestWeb.ChannelCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import DelivestWeb.ChannelCase

      @endpoint DelivestWeb.Endpoint
    end
  end

  setup tags do
    Delivest.DataCase.setup_sandbox(tags)
    :ok
  end
end
