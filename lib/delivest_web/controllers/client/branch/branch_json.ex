defmodule DelivestWeb.Client.Branch.BranchJSON do
  def index(%{
        branches: branches,
        notification_capabilities: capabilities,
        analytics_capabilities: analytics
      }) do
    %{data: for(branch <- branches, do: branch_data(branch, capabilities, analytics))}
  end

  def show(%{
        branch: branch,
        notification_capabilities: capabilities,
        analytics_capabilities: analytics
      }) do
    %{data: branch_data(branch, capabilities, analytics)}
  end

  defp branch_data(branch, capabilities, analytics) do
    %{
      id: branch.id,
      name: branch.name,
      slug: branch.slug,
      is_active: branch.is_active,
      branch_info: branch_info(branch.info, branch, capabilities, analytics)
    }
  end

  defp effective_time(%{delivery_time: nil}), do: nil
  defp effective_time(%{delivery_time: time} = info), do: time + intake(info).extra_minutes

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

  defp payment_methods(%{payments: %Delivest.Identity.Branch.PaymentSettings{} = payments}),
    do:
      Delivest.Identity.Branch.PaymentSettings.enabled(
        payments,
        Delivest.Integrations.Yookassa.ready?()
      )

  defp payment_methods(_info), do: [:cash, :card_offline]

  defp loyalty(%{loyalty: %Delivest.Identity.Branch.LoyaltySettings{}}, branch) do
    loyalty = Delivest.Loyalty.settings(branch)
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

  defp loyalty(_info, _branch),
    do: %{
      enabled: false,
      per_rubles: nil,
      stars: nil,
      expire_days: nil,
      spend_enabled: false,
      max_percent: nil
    }

  defp branch_info(%Ecto.Association.NotLoaded{}, _branch, _capabilities, _analytics), do: nil
  defp branch_info(nil, _branch, _capabilities, _analytics), do: nil

  defp branch_info(info, branch, capabilities, analytics) do
    %{
      id: info.id,
      address: info.address,
      city: info.city,
      timezone: Delivest.LocalTime.timezone(info),
      latitude: info.latitude,
      longitude: info.longitude,
      phone_number: info.phone_number,
      delivery_time: effective_time(info),
      manual_rating: info.manual_rating,
      intake: intake(info),
      fulfillment_methods: Delivest.Identity.Branch.FulfillmentSettings.enabled(info.fulfillment),
      payment_methods: payment_methods(info),
      loyalty: loyalty(info, branch),
      notifications_enabled: MapSet.member?(capabilities, branch.id),
      analytics_funnel_enabled: MapSet.member?(analytics, branch.id),
      working_hours: info.working_hours || %{},
      special_hours: info.special_hours || %{},
      vk_url: info.vk_url,
      whatsapp_url: info.whatsapp_url,
      instagram_url: info.instagram_url,
      ycart_settings: info.ycart_settings || %{}
    }
  end
end
