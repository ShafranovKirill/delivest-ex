defmodule Delivest.Integrations.Crm.Registry do
  @modules [Delivest.Integrations.Frontpad]

  def modules, do: @modules

  def keys, do: Enum.map(@modules, & &1.key())

  def fetch(key) do
    case Enum.find(@modules, &(to_string(&1.key()) == to_string(key))) do
      nil -> {:error, :unknown_provider}
      module -> {:ok, module}
    end
  end
end
