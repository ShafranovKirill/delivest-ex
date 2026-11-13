defmodule Delivest.Integrations.Availability do
  @moduledoc "Effective integration permissions derived from saved domain settings."

  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.{BranchSettings, Registry}

  def crm(%BranchSettings{} = settings, provider) do
    provider = normalize(provider)
    selected? = settings.provider == provider
    configured? = Crm.configured?(settings, provider)
    desired? = settings.enabled == true and selected?
    orders? = desired? and configured? and (settings.sources || []) != []
    catalog? = desired? and configured? and provider == :frontpad
    stops? = desired? and configured? and stops_enabled?(settings, provider)

    reason =
      cond do
        not desired? -> :disabled
        not configured? -> :not_configured
        settings.sources == [] -> :no_sources
        true -> nil
      end

    %{
      id: provider,
      desired?: desired?,
      configured?: configured?,
      effective?: orders? or catalog? or stops?,
      generation: settings.generation || 0,
      reason: reason,
      capabilities: %{orders: orders?, catalog: catalog?, stops: stops?}
    }
  end

  def crm(branch_id, provider), do: branch_id |> Crm.get_branch_settings() |> crm(provider)

  def crm_allowed?(branch_id, provider, capability, generation \\ nil) do
    state = crm(branch_id, provider)

    Map.get(state.capabilities, capability, false) and
      (is_nil(generation) or generation == state.generation)
  end

  defp normalize(provider) when is_atom(provider), do: provider

  defp normalize(provider) when is_binary(provider),
    do: Enum.find(Registry.keys(), &(to_string(&1) == provider))

  defp normalize(_provider), do: nil

  defp stops_enabled?(settings, provider) do
    case Registry.fetch(provider) do
      {:ok, module} ->
        function_exported?(module, :stops_enabled?, 1) and
          module.stops_enabled?(Map.get(settings, provider))

      _ ->
        false
    end
  end
end
