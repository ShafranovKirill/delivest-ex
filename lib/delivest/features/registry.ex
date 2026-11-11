defmodule Delivest.Features.Registry do
  @moduledoc "Allowlisted host-managed feature keys, independent of background jobs."
  @features ["segments", "notifications", "marketing_policies", "analytics_funnel"]

  @dependencies %{"marketing_policies" => ["segments", "notifications"]}
  @permission_prefixes %{"segments." => "segments", "marketing." => "marketing_policies"}

  def known?(feature), do: feature in @features
  def dependencies(feature), do: Map.get(@dependencies, feature, [])

  def permission_features, do: @permission_prefixes |> Map.values() |> Enum.uniq()

  def permission_feature(permission) when is_binary(permission) do
    Enum.find_value(@permission_prefixes, fn {prefix, feature} ->
      if String.starts_with?(permission, prefix), do: feature
    end)
  end

  def permission_feature(_), do: nil

  def dependents(feature),
    do: for({key, dependencies} <- @dependencies, feature in dependencies, do: key)
end
