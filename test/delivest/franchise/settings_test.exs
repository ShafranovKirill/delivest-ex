defmodule Delivest.Franchise.SettingsTest do
  use ExUnit.Case, async: true

  alias Delivest.Franchise.Settings

  test "accepts light and dark as default themes" do
    for theme <- ["light", "dark"] do
      changeset = Settings.changeset(%Settings{}, %{default_theme: theme})
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :default_theme) == theme
    end
  end

  test "rejects unsupported and missing default themes" do
    refute Settings.changeset(%Settings{}, %{default_theme: "system"}).valid?
    refute Settings.changeset(%Settings{}, %{default_theme: nil}).valid?
    refute Settings.changeset(%Settings{}, %{"default_theme" => ""}).valid?
  end

  test "legacy Yandex credentials are read-only" do
    settings = %Settings{yandex_org_id: "old-org", yandex_api_key: "old-key"}

    changeset =
      Settings.changeset(settings, %{
        yandex_org_id: "new-org",
        yandex_api_key: "new-key"
      })

    assert Ecto.Changeset.get_field(changeset, :yandex_org_id) == "old-org"
    assert Ecto.Changeset.get_field(changeset, :yandex_api_key) == "old-key"
  end
end
