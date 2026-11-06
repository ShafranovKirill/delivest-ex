defmodule Delivest.Repo.Migrations.AddCrmCommandDeliveries do
  use Ecto.Migration

  def change do
    create table(:crm_command_deliveries, primary_key: false) do
      add :job_id, :bigint, primary_key: true

      add :order_id, references(:orders, type: :uuid, on_delete: :delete_all), null: false
      add :branch_id, references(:branches, type: :uuid, on_delete: :delete_all), null: false
      add :event_id, references(:domain_events, type: :uuid, on_delete: :nilify_all)
      add :phase, :string, null: false, default: "pending"
      add :last_error, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:crm_command_deliveries, [:event_id], where: "event_id IS NOT NULL")
    create index(:crm_command_deliveries, [:order_id, :job_id])
    create index(:crm_command_deliveries, [:phase, :updated_at])
  end
end
