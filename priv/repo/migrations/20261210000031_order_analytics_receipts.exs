defmodule Delivest.Repo.Migrations.OrderAnalyticsReceipts do
  use Ecto.Migration

  def change do
    create table(:advertising_order_receipts, primary_key: false) do
      add :order_id, references(:orders, type: :uuid), primary_key: true
      add :link_id, references(:advertising_links, type: :uuid), null: false
      add :landing_branch_id, references(:branches, type: :uuid), null: false
      add :clicked_at, :utc_datetime_usec, null: false
      add :as_of_at, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:advertising_order_receipts, [:link_id, :inserted_at])

    create table(:funnel_order_receipts, primary_key: false) do
      add :order_id, references(:orders, type: :uuid), primary_key: true
      add :session_id, :uuid, null: false
      add :owner_kind, :string, null: false
      add :session_started_at, :utc_datetime_usec, null: false
      add :session_last_at, :utc_datetime_usec, null: false
      add :source_type, :string, null: false
      add :utm_source, :string
      add :utm_medium, :string
      add :utm_campaign, :string
      add :as_of_at, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:funnel_order_receipts, [:session_id])
  end
end
