defmodule DelivestWeb.Client.Branch.BranchJSON do
  def index(%{
        branches: branches,
        notification_capabilities: capabilities,
        analytics_capabilities: analytics,
        links_capabilities: links,
        delivery_settings: delivery,
        payment_ready: payment_ready,
        loyalty_policy: loyalty_policy,
        franchise_maintenance: franchise_maintenance,
        timezones: timezones
      }) do
    prepared =
      {delivery, payment_ready, loyalty_policy, timezones, franchise_maintenance}

    %{
      data:
        for(branch <- branches, do: branch_data(branch, capabilities, analytics, links, prepared))
    }
  end

  def show(%{
        branch: branch,
        notification_capabilities: capabilities,
        analytics_capabilities: analytics,
        links_capabilities: links,
        delivery_settings: delivery,
        payment_ready: payment_ready,
        loyalty_policy: loyalty_policy,
        franchise_maintenance: franchise_maintenance,
        timezones: timezones
      }) do
    %{
      data:
        branch_data(
          branch,
          capabilities,
          analytics,
          links,
          {delivery, payment_ready, loyalty_policy, timezones, franchise_maintenance}
        )
    }
  end

  defp branch_data(branch, capabilities, analytics, links, prepared) do
    %{
      id: branch.id,
      name: branch.name,
      slug: branch.slug,
      is_active: branch.is_active,
      branch_info: branch_info(branch.info, branch, capabilities, analytics, links, prepared)
    }
  end

  defp effective_time(%{timing: %Delivest.Oms.OrderTiming.Settings{mode: :calculated}} = info) do
    settings = timing(info)

    settings.kitchen_minutes + settings.packing_minutes + settings.travel_minutes +
      intake(info).extra_minutes
  end

  defp effective_time(%{delivery_time: time}) when is_integer(time) and time > 0, do: time
  defp effective_time(_info), do: 60

  defp fixed_time(%{delivery_time: time}) when is_integer(time) and time > 0, do: time
  defp fixed_time(_info), do: 60

  defp intake(%{intake: %Delivest.Identity.Branch.IntakeSettings{} = intake}) do
    status = Delivest.Intake.status_of(intake, DateTime.utc_now())

    %{
      mode: status.mode,
      extra_minutes: status.extra_minutes,
      until: status.until,
      reason: status.reason
    }
  end

  defp intake(_info), do: %{mode: :normal, extra_minutes: 0, until: nil, reason: nil}

  defp payment_methods(
         %{payments: %Delivest.Identity.Branch.PaymentSettings{} = payments},
         ready?
       ),
       do:
         Delivest.Identity.Branch.PaymentSettings.enabled(
           payments,
           ready?
         )

  defp payment_methods(_info, _ready?), do: [:cash, :card_offline]

  defp delivery_settings(branch_id, prepared) do
    settings = Map.fetch!(prepared, branch_id)

    %{
      map_address: settings.map_address != false,
      address_mode_set: settings.address_mode_set == true,
      show_city: settings.map_address == false and settings.show_city == true,
      operator_address: settings.map_address == false and settings.operator_address == true
    }
  end

  defp loyalty(%{loyalty: %Delivest.Identity.Branch.LoyaltySettings{} = loyalty}, branch, policy) do
    loyalty = %{
      loyalty
      | per_rubles: policy.per_rubles,
        stars: policy.stars,
        expire_days: policy.expire_days
    }

    enabled = loyalty.enabled and Delivest.Gateway.own?(branch, :loyalty)

    %{
      enabled: enabled,
      per_rubles: loyalty.per_rubles,
      stars: loyalty.stars,
      expire_days: loyalty.expire_days,
      spend_enabled: enabled and loyalty.spend_enabled == true,
      max_percent: loyalty.max_percent || 50
    }
  end

  defp loyalty(_info, _branch, _policy),
    do: %{
      enabled: false,
      per_rubles: nil,
      stars: nil,
      expire_days: nil,
      spend_enabled: false,
      max_percent: nil
    }

  defp branch_info(
         %Ecto.Association.NotLoaded{},
         _branch,
         _capabilities,
         _analytics,
         _links,
         _prepared
       ),
       do: nil

  defp branch_info(nil, _branch, _capabilities, _analytics, _links, _prepared), do: nil

  defp branch_info(
         info,
         branch,
         capabilities,
         analytics,
         links,
         {delivery, payment_ready, loyalty_policy, timezones, franchise_maintenance}
       ) do
    %{
      id: info.id,
      address: info.address,
      city: info.city,
      timezone: Map.fetch!(timezones, branch.id),
      latitude: info.latitude,
      longitude: info.longitude,
      phone_number: info.phone_number,
      delivery_time: effective_time(info),
      timing_mode: timing(info).mode,
      fixed_delivery_minutes: fixed_time(info),
      kitchen_minutes: timing(info).kitchen_minutes,
      packing_minutes: timing(info).packing_minutes,
      travel_minutes: timing(info).travel_minutes,
      manual_rating: info.manual_rating,
      intake: intake(info),
      maintenance:
        Delivest.Storefront.Maintenance.status_of(franchise_maintenance, info.maintenance_enabled),
      fulfillment_methods: Delivest.Identity.Branch.FulfillmentSettings.enabled(info.fulfillment),
      delivery: delivery_settings(branch.id, delivery),
      payment_methods: payment_methods(info, payment_ready),
      loyalty: loyalty(info, branch, loyalty_policy),
      notifications_enabled: MapSet.member?(capabilities, branch.id),
      analytics_funnel_enabled: MapSet.member?(analytics, branch.id),
      analytics_links_enabled: MapSet.member?(links, branch.id),
      working_hours: info.working_hours || %{},
      special_hours: info.special_hours || %{},
      vk_url: info.vk_url,
      whatsapp_url: info.whatsapp_url,
      instagram_url: info.instagram_url,
      ycart_settings: info.ycart_settings || %{},
      vk_ads: Delivest.Identity.Branch.VkAdsSettings.public_config(info.vk_ads)
    }
  end

  defp timing(%{timing: %Delivest.Oms.OrderTiming.Settings{} = settings}), do: settings
  defp timing(_info), do: %Delivest.Oms.OrderTiming.Settings{}
end
