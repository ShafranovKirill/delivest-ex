defmodule DelivestWeb.Client.Branch.BranchJSON do
  def index(%{branches: branches}) do
    %{data: for(branch <- branches, do: branch_data(branch))}
  end

  def show(%{branch: branch}) do
    %{data: branch_data(branch)}
  end

  defp branch_data(branch) do
    %{
      id: branch.id,
      name: branch.name,
      slug: branch.slug,
      is_active: branch.is_active,
      branch_info: branch_info(branch.info, branch)
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

  defp loyalty(%{loyalty: %Delivest.Identity.Branch.LoyaltySettings{} = loyalty}, branch) do
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

  defp branch_info(%Ecto.Association.NotLoaded{}, _branch), do: nil
  defp branch_info(nil, _branch), do: nil

  defp branch_info(info, branch) do
    %{
      id: info.id,
      address: info.address,
      city: info.city,
      latitude: info.latitude,
      longitude: info.longitude,
      phone_number: info.phone_number,
      delivery_time: effective_time(info),
      intake: intake(info),
      payment_methods: payment_methods(info),
      loyalty: loyalty(info, branch),
      working_hours: info.working_hours || %{},
      special_hours: info.special_hours || %{},
      vk_url: info.vk_url,
      whatsapp_url: info.whatsapp_url,
      instagram_url: info.instagram_url,
      ycart_settings: info.ycart_settings || %{}
    }
  end
end
