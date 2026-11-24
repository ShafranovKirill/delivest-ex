defmodule Delivest.Features.Registry do
  @moduledoc "Allowlisted host-managed feature keys, independent of background jobs."
  @features [
    "segments",
    "notifications",
    "marketing_policies",
    "couriers",
    "product_import",
    "event_log",
    "stocks",
    "promotions",
    "loyalty",
    "kitchen",
    "analytics_basic",
    "analytics_funnel",
    "analytics_extended",
    "analytics_franchise",
    "analytics_links",
    "yandex_ads",
    "yandex_browser",
    "yandex_conversions",
    "yandex_ecommerce",
    "yandex_feed",
    "yandex_costs"
  ]

  @dependencies %{
    "analytics_funnel" => ["analytics_basic"],
    "analytics_extended" => ["analytics_basic"],
    "analytics_links" => ["analytics_basic"],
    "marketing_policies" => ["segments", "notifications"],
    "analytics_franchise" => ["analytics_extended"],
    "yandex_browser" => ["yandex_ads"],
    "yandex_conversions" => ["yandex_ads"],
    "yandex_ecommerce" => ["yandex_ads"],
    "yandex_feed" => ["yandex_ads"],
    "yandex_costs" => ["yandex_ads"]
  }
  @permission_prefixes %{"segments." => "segments", "marketing." => "marketing_policies"}

  alias Delivest.Integrations.StaffAccess

  def known?(feature), do: feature in @features or StaffAccess.permission?(feature)
  def features, do: @features ++ StaffAccess.keys()
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
