defmodule Delivest.Fiscal.Registry do
  @modules [Delivest.Integrations.AtolOnline]

  def modules, do: @modules

  def fetch(key) do
    case Enum.find(@modules, &(to_string(&1.key()) == to_string(key))) do
      nil -> {:error, :unknown_provider}
      module -> {:ok, module}
    end
  end
end
