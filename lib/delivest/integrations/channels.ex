defmodule Delivest.Integrations.Channels do
  alias Delivest.Integrations.Channels.Registry

  def list, do: Enum.map(Registry.modules(), &{&1.key(), &1.name()})

  def name("app"), do: "app"
  def name("staff"), do: "staff"

  def name(key) do
    case Registry.fetch(key) do
      {:ok, module} -> module.name()
      _error -> to_string(key)
    end
  end
end
