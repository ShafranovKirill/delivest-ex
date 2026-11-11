defmodule Delivest.Notifications.SourceRegistry do
  @moduledoc "Trusted source callbacks for currentness checks."

  @sources %{
    "marketing_reward" => Delivest.Marketing
  }
  @source_features %{"marketing_reward" => "marketing_policies"}

  def known?(type), do: Map.has_key?(@sources, type)

  def feature_disabled(feature, scope) do
    if feature in Map.values(@source_features),
      do: Delivest.Notifications.Dispatch.on_source_disable(scope)

    :ok
  end

  def descriptor(type, source_id, client_id) do
    with {:ok, module} <- Map.fetch(@sources, type),
         {:ok, feature} <- Map.fetch(@source_features, type),
         {:ok, scope, source_generation} <- module.notification_scope(source_id, client_id),
         {:ok, scope_key} <- Delivest.Features.scope_key(scope) do
      {:ok,
       %{feature: feature, scope: scope, scope_key: scope_key, generation: source_generation}}
    else
      _ -> {:error, :invalid_source}
    end
  end

  def current?(type, source_id, client_id, phase) when phase in [:send, :show] do
    case Map.fetch(@sources, type) do
      {:ok, module} -> module.notification_current?(source_id, client_id, phase)
      :error -> false
    end
  end

  def current?(_, _, _, _), do: false

  def filter_current(notices, phase) when phase in [:send, :show] do
    current_by_type =
      notices
      |> Enum.group_by(& &1.source_type)
      |> Map.new(fn {type, group} ->
        ids = Enum.map(group, & &1.source_id)

        current =
          case Map.fetch(@sources, type) do
            {:ok, module} when is_atom(module) ->
              if function_exported?(module, :notification_current_many?, 3) do
                module.notification_current_many?(ids, hd(group).client_id, phase)
              else
                MapSet.new(
                  Enum.filter(ids, &module.notification_current?(&1, hd(group).client_id, phase))
                )
              end

            :error ->
              MapSet.new()
          end

        {type, current}
      end)

    Enum.filter(notices, fn notice ->
      MapSet.member?(Map.fetch!(current_by_type, notice.source_type), notice.source_id)
    end)
  end
end
