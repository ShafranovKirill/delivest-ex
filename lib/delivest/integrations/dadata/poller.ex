defmodule Delivest.Integrations.Dadata.Poller do
  @behaviour Delivest.Integrations.Poller

  alias Delivest.Integrations.{Dadata, Health}

  @impl true
  def key, do: :dadata

  @impl true
  def interval, do: 3600

  @impl true
  def targets, do: ["all"]

  @impl true
  def poll(_target) do
    if Dadata.active?() do
      Health.check(:dadata, nil)
      :done
    else
      :done
    end
  end
end
