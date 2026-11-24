defmodule Delivest.Integrations.HardSwitchRuntimeTest do
  use Delivest.DataCase, async: true

  import Delivest.YandexEdaFixtures

  alias Delivest.Features.Gate
  alias Delivest.Identity.Branch.VkAdsSettings
  alias Delivest.Integrations.{StaffAccess, YandexEda}
  alias Delivest.Integrations.YandexEda.PushApi
  alias Delivest.Integrations.AtolOnline.KktPoller
  alias Delivest.Integrations.YandexDelivery

  defp set_provider(provider, enabled) do
    key = "integration_#{provider}"

    %Gate{feature: key, scope_key: "franchise", enabled: enabled, generation: 1}
    |> Repo.insert!(on_conflict: {:replace, [:enabled]}, conflict_target: [:feature, :scope_key])
  end

  test "Yandex Eda revokes an issued token and stops outgoing calls while disabled" do
    settings = credentials()
    assert {:ok, token} = YandexEda.issue_token(settings.client_id, settings.client_secret)
    assert YandexEda.valid_token?(token)

    set_provider(:yandex_eda, false)
    refute StaffAccess.allowed?(:yandex_eda)
    refute YandexEda.valid_token?(token)

    assert {:error, :invalid_client} =
             YandexEda.issue_token(settings.client_id, settings.client_secret)

    assert {:error, :disabled} = PushApi.reload_menu(settings, "restaurant", "menu")
    assert YandexEda.restaurants() == []

    set_provider(:yandex_eda, true)
    assert YandexEda.valid_token?(token)
  end

  test "disabled providers do not expose VK tracking or schedule pollers" do
    vk = %VkAdsSettings{enabled: true, privacy_approved: true, counter_id: "3817108"}
    assert VkAdsSettings.public_config(vk).enabled

    set_provider(:vk_ads, false)
    set_provider(:yandex_delivery, false)
    set_provider(:atol, false)

    assert VkAdsSettings.public_config(vk) == %{enabled: false, counter_id: nil}
    assert YandexDelivery.active_branches() == []
    assert KktPoller.targets() == []

    set_provider(:vk_ads, true)
    assert VkAdsSettings.public_config(vk).enabled
  end
end
