defmodule Delivest.Availability do
  @moduledoc "Single read contract over existing feature gates and integration settings."

  alias Delivest.{Features, Identity}
  alias Delivest.Features.{Gate, Registry}
  alias Delivest.Integrations.Availability, as: IntegrationAvailability
  alias Delivest.Integrations.{Crm, Health, Journal}
  alias Delivest.Repo

  def feature_snapshot(feature, scope), do: Features.snapshot(feature, scope)
  def feature_enabled?(feature, scope), do: Features.enabled?(feature, scope)

  def feature_still_enabled?(feature, scope, generation),
    do: Features.still_enabled?(feature, scope, generation)

  def feature(feature, scope) do
    with true <- Registry.known?(feature),
         {:ok, key} <- Features.scope_key(scope) do
      local = Repo.get_by(Gate, feature: feature, scope_key: key)

      parent =
        if key == "franchise",
          do: local,
          else: Repo.get_by(Gate, feature: feature, scope_key: "franchise")

      effective? = feature_enabled?(feature, scope)

      %{
        id: feature,
        scope: scope,
        configured?: true,
        desired?: !!(local && local.enabled),
        effective?: effective?,
        generation: %{
          franchise: parent && parent.generation,
          branch: if(key == "franchise", do: nil, else: local && local.generation)
        },
        configuration: :not_required,
        connection: nil,
        activity: nil,
        obligations: %{},
        actions: [:view],
        reason:
          cond do
            effective? -> nil
            local && local.enabled -> :dependency_disabled
            true -> :disabled
          end,
        capabilities: %{execution: effective?}
      }
    else
      _ -> {:error, :unknown_feature}
    end
  end

  def crm(branch_id, provider, staff \\ nil) do
    state = IntegrationAvailability.crm(branch_id, provider)
    activity = Journal.list(provider, branch_id, limit: 1) |> List.first()
    work = Crm.work_summary(branch_id)
    actions = actions(staff, branch_id, state)

    Map.merge(state, %{
      scope: {:branch, branch_id},
      configuration: if(state.configured?, do: :complete, else: :missing),
      connection: Health.get(provider, branch_id),
      activity: activity,
      obligations: Map.get(work, to_string(provider), %{unsent: 0, uncertain: 0, accepted: 0}),
      actions: actions
    })
  end

  def crm_allowed?(branch_id, provider, capability, generation \\ nil),
    do: IntegrationAvailability.crm_allowed?(branch_id, provider, capability, generation)

  defp actions(nil, _branch_id, _state), do: [:view]

  defp actions(staff, branch_id, state) do
    if Identity.authorize(staff, "integrations.update", branch_id) == :ok do
      [:view, :configure] ++
        if(state.configured?, do: [:check], else: []) ++
        cond do
          state.desired? -> [:disable]
          state.configured? -> [:enable]
          true -> []
        end
    else
      [:view]
    end
  end
end
