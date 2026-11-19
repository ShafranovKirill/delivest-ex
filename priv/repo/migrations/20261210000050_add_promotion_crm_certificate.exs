defmodule Delivest.Repo.Migrations.AddPromotionCrmCertificate do
  use Ecto.Migration

  def change do
    alter table(:promotions) do
      add :crm_certificate, :map
    end
  end
end
