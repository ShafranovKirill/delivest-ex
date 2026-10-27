defmodule Delivest.Oms.OrderSource do
  alias Delivest.Integrations.Channels.Registry

  @own ~w(app staff)

  def own, do: @own

  def all, do: @own ++ Enum.map(Registry.keys(), &to_string/1)

  def valid?(source), do: to_string(source) in all()
end
