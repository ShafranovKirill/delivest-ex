defmodule Delivest.Repo.Migrations.CustomerNotifications do
  use Ecto.Migration

  def up do
    create table(:customer_notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :client_id, references(:clients, type: :binary_id, on_delete: :delete_all), null: false
      add :branch_id, references(:branches, type: :binary_id, on_delete: :delete_all), null: false
      add :idempotency_key, :string, null: false
      add :source_type, :string, null: false
      add :source_id, :binary_id, null: false
      add :source_feature, :string, null: false
      add :source_scope_key, :string, null: false
      add :source_generation_franchise, :bigint, null: false
      add :source_generation_branch, :bigint, null: false
      add :notification_generation_franchise, :bigint, null: false
      add :notification_generation_branch, :bigint, null: false
      add :title, :string, null: false
      add :body, :string, null: false
      add :cta, :map
      add :expires_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:customer_notifications, [:idempotency_key])
    create index(:customer_notifications, [:client_id, :branch_id, :inserted_at, :id])

    create index(:customer_notifications, [:source_type, :source_id],
             name: :customer_notification_source_idx
           )

    create table(:customer_notification_intents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :notification_id,
          references(:customer_notifications, type: :binary_id, on_delete: :delete_all),
          null: false

      add :channel, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :job_id, :bigint
      add :fanout_cursor, :binary_id
      add :fanout_complete, :boolean, null: false, default: false
      add :due_at, :utc_datetime_usec, null: false
      add :last_error, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:customer_notification_intents, [:notification_id, :channel])
    create index(:customer_notification_intents, [:status, :due_at])

    create table(:customer_notification_push_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :intent_id,
          references(:customer_notification_intents, type: :binary_id, on_delete: :delete_all),
          null: false

      add :subscription_id, :binary_id, null: false
      add :job_id, :bigint
      add :status, :string, null: false, default: "queued"
      add :last_error, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:customer_notification_push_deliveries, [:intent_id, :subscription_id])
    create index(:customer_notification_push_deliveries, [:status, :updated_at])

    create table(:customer_notification_dismissals, primary_key: false) do
      add :notification_id,
          references(:customer_notifications, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :device_id, :binary_id, primary_key: true
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create table(:customer_notification_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :notification_id,
          references(:customer_notifications, type: :binary_id, on_delete: :delete_all),
          null: false

      add :device_id, :binary_id, null: false
      add :kind, :string, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:customer_notification_events, [:notification_id, :device_id, :kind])

    create table(:customer_notification_consents, primary_key: false) do
      add :client_id, references(:clients, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :sms, :boolean, null: false, default: false
      add :push, :boolean, null: false, default: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create table(:customer_notification_consent_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :client_id, references(:clients, type: :binary_id, on_delete: :delete_all), null: false
      add :channel, :string, null: false
      add :old_value, :boolean, null: false
      add :new_value, :boolean, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:customer_notification_consent_events, [:client_id, :inserted_at])
  end

  def down do
    drop_if_exists table(:customer_notification_consent_events)
    drop_if_exists table(:customer_notification_consents)
    drop_if_exists table(:customer_notification_events)
    drop_if_exists table(:customer_notification_dismissals)
    drop_if_exists table(:customer_notification_push_deliveries)
    drop_if_exists table(:customer_notification_intents)
    drop_if_exists table(:customer_notifications)
  end
end
