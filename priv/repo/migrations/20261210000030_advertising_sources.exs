defmodule Delivest.Repo.Migrations.AdvertisingSources do
  use Ecto.Migration

  def change do
    create table(:advertising_links, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :branch_id, references(:branches, type: :uuid), null: false
      add :token, :string, null: false
      add :campaign, :string, null: false
      add :name, :string, null: false
      add :enabled, :boolean, null: false, default: true
      add :archived_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:advertising_links, [:token])
    create index(:advertising_links, [:branch_id, :inserted_at, :id])

    create table(:advertising_clicks, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :link_id, references(:advertising_links, type: :uuid), null: false
      add :branch_id, references(:branches, type: :uuid), null: false
      add :guest_id, :uuid
      add :client_id, references(:clients, type: :uuid)
      add :clicked_at, :utc_datetime_usec, null: false
    end

    create constraint(:advertising_clicks, :advertising_click_owner,
             check: "guest_id IS NOT NULL OR client_id IS NOT NULL"
           )

    create index(:advertising_clicks, [:guest_id, :clicked_at])
    create index(:advertising_clicks, [:client_id, :clicked_at])
    create index(:advertising_clicks, [:clicked_at, :id])

    create table(:advertising_guest_claims, primary_key: false) do
      add :guest_id, :uuid, primary_key: true
      add :client_id, references(:clients, type: :uuid), null: false
      add :claimed_at, :utc_datetime_usec, null: false
    end

    create index(:advertising_guest_claims, [:client_id])
    create index(:advertising_guest_claims, [:claimed_at, :guest_id])

    create table(:client_first_sources, primary_key: false) do
      add :client_id, references(:clients, type: :uuid), primary_key: true
      add :link_id, references(:advertising_links, type: :uuid), null: false
      add :landing_branch_id, references(:branches, type: :uuid), null: false
      add :clicked_at, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end
  end
end
