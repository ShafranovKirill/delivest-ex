defmodule Delivest.Repo.Migrations.AddVkAdsSettingsToBranchInfo do
  use Ecto.Migration

  def change do
    alter table(:branch_info) do
      add :vk_ads, :map, default: %{"enabled" => false}, null: false
    end
  end
end
