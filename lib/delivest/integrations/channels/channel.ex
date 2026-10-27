defmodule Delivest.Integrations.Channels.Channel do
  @callback key() :: atom()
  @callback name() :: String.t()
  @callback settings_schema() :: module()
  @callback configured?(settings :: struct() | nil) :: boolean()
end
