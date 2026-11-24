defmodule Delivest.Identity.Branch.VkAdsSettingsTest do
  use Delivest.DataCase, async: true

  alias Delivest.Identity.Branch.VkAdsSettings

  test "requires a positive numeric ID and confirmation before activation" do
    invalid = VkAdsSettings.changeset(%VkAdsSettings{}, %{enabled: true, counter_id: "0"})
    refute invalid.valid?
    assert invalid.errors[:counter_id]
    assert invalid.errors[:privacy_approved]

    valid =
      VkAdsSettings.changeset(%VkAdsSettings{}, %{
        enabled: true,
        counter_id: "3817108",
        privacy_approved: true
      })

    assert valid.valid?
  end

  test "corrupt stored ID stays disabled and cannot be enabled without correction" do
    stored = %VkAdsSettings{counter_id: "3817108\n", privacy_approved: true}
    refute VkAdsSettings.changeset(stored, %{enabled: true}).valid?

    assert VkAdsSettings.public_config(%{stored | enabled: true}) ==
             %{enabled: false, counter_id: nil}
  end
end
