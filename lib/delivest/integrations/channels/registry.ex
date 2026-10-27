defmodule Delivest.Integrations.Channels.Registry do
  @modules []

  def modules, do: @modules

  def keys, do: Enum.map(@modules, & &1.key())

  def fetch(key) do
    case Enum.find(@modules, &(to_string(&1.key()) == to_string(key))) do
      nil -> {:error, :unknown_channel}
      module -> {:ok, module}
    end
  end
end
