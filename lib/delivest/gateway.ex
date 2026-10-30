defmodule Delivest.Gateway do
  alias Delivest.Identity.Branch
  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.BranchSettings

  @areas [:kitchen, :pos, :couriers, :receipts, :statuses, :menu, :stops, :loyalty]

  def areas, do: @areas

  def mode(%Branch{info: %{crm: %BranchSettings{} = settings}}) do
    case BranchSettings.active_provider(settings) do
      nil -> own()
      provider -> crm(provider, settings)
    end
  end

  def mode(_branch), do: own()

  def active?(branch), do: mode(branch).provider != nil

  def owner(branch, area) when area in @areas, do: Map.fetch!(mode(branch).areas, area)

  def own?(branch, area), do: owner(branch, area) == :own

  def crm?(branch, area), do: owner(branch, area) == :crm

  defp own, do: %{provider: nil, name: nil, areas: Map.new(@areas, &{&1, :own})}

  defp crm(provider, settings) do
    capabilities = Crm.capabilities(provider)

    %{
      provider: provider,
      name: Crm.provider_name(provider),
      areas: %{
        kitchen: :crm,
        statuses: :crm,
        pos: owner_if(:own_pos in capabilities),
        couriers: owner_if(:delivery in capabilities),
        receipts: owner_if(:own_pos in capabilities),
        menu: owner_if(settings.menu_source == :crm and Crm.menu_source?(provider)),
        stops: owner_if(Crm.stops_source?(provider)),
        loyalty: :crm
      }
    }
  end

  defp owner_if(true), do: :crm
  defp owner_if(_), do: :own
end
