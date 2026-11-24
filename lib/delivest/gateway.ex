defmodule Delivest.Gateway do
  alias Delivest.Identity.Branch
  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Integrations.Crm.Registry
  alias Delivest.Integrations.StaffAccess

  @areas [:kitchen, :pos, :couriers, :receipts, :statuses, :menu, :stops, :loyalty]

  def areas, do: @areas

  def mode(branch), do: mode(branch, nil)

  def mode(%Branch{info: %{crm: %BranchSettings{} = settings}}, access) do
    case BranchSettings.active_provider(settings) do
      nil ->
        own()

      provider ->
        case Registry.fetch(provider) do
          {:ok, module} ->
            enabled? =
              if is_map(access),
                do: Map.get(access, module.key(), false),
                else: StaffAccess.allowed?(module.key())

            if enabled?, do: crm(provider, settings), else: own()

          {:error, :unknown_provider} ->
            crm(provider, settings)
        end
    end
  end

  def mode(_branch, _access), do: own()

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
