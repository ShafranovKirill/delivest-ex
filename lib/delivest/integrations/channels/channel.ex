defmodule Delivest.Integrations.Channels.Channel do
  @callback key() :: atom()
  @callback name() :: String.t()
  @callback settings_schema() :: module()
  @callback configured?(settings :: struct() | nil) :: boolean()
  @callback stops_changed(branch_id :: binary()) :: :ok
  @callback menu_changed(branch_id :: binary()) :: :ok
  @callback health_check(settings :: struct()) :: :ok | {:error, term()}

  @optional_callbacks health_check: 1
end
