defmodule Delivest.Couriers.Registry do
  @modules [Delivest.Couriers.StaffProvider]

  def modules, do: @modules

  def keys, do: Enum.map(@modules, & &1.key())

  def fetch(key) do
    case Enum.find(@modules, &(&1.key() == key)) do
      nil -> {:error, :unknown_provider}
      module -> {:ok, module}
    end
  end
end
