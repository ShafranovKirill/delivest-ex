defmodule Delivest.Storefront.BranchProjection do
  @moduledoc "Prepares branch JSON dependencies in a fixed number of reads."

  alias Delivest.{Delivery, Features, LocalTime, Loyalty}
  alias Delivest.Identity.Branch.{LoyaltySettings, PaymentSettings}
  alias Delivest.Integrations.Yookassa

  @features ["notifications", "analytics_funnel", "analytics_links"]

  def prepare(branches) when is_list(branches) do
    ids = Enum.map(branches, & &1.id)
    with_info = Enum.filter(branches, &match?(%{info: %{id: _}}, &1))
    info_ids = Enum.map(with_info, & &1.id)
    gates = Features.enabled_branches_many(@features, ids)

    delivery = if info_ids == [], do: %{}, else: Delivery.get_settings_many(info_ids)

    payment_ready =
      if Enum.any?(with_info, &match?(%PaymentSettings{}, &1.info.payments)),
        do: Yookassa.ready_snapshot?(),
        else: false

    loyalty_policy =
      if Enum.any?(with_info, &match?(%LoyaltySettings{}, &1.info.loyalty)),
        do: Loyalty.policy(),
        else: nil

    fallback_timezone =
      if Enum.any?(with_info, &is_nil(&1.info.timezone)),
        do: LocalTime.timezone(),
        else: nil

    timezones =
      Map.new(with_info, fn branch ->
        {branch.id, branch.info.timezone || fallback_timezone}
      end)

    %{
      branches: branches,
      notification_capabilities: Map.fetch!(gates, "notifications"),
      analytics_capabilities: Map.fetch!(gates, "analytics_funnel"),
      links_capabilities: Map.fetch!(gates, "analytics_links"),
      delivery_settings: delivery,
      payment_ready: payment_ready,
      loyalty_policy: loyalty_policy,
      timezones: timezones
    }
  end
end
