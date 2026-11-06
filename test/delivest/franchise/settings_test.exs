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
end
