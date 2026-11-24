defmodule Delivest.Repo.Migrations.AddDeliveryMeasurementFacts do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :initial_promised_delivery_at, :utc_datetime
      add :promised_delivery_at, :utc_datetime
      add :delivered_at, :utc_datetime
      add :delivery_actual_source, :string
      add :delivery_actual_received_at, :utc_datetime
    end

    create table(:delivery_promise_history, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false
      add :promised_at, :utc_datetime, null: false
      add :source, :string, null: false
      add :staff_id, :binary_id
      add :reason, :text
      add :recorded_at, :utc_datetime_usec, null: false
    end

    create index(:delivery_promise_history, [:order_id, :recorded_at])

    create table(:delivery_actual_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false
      add :event_id, :string, null: false
      add :source, :string, null: false
      add :occurred_at, :utc_datetime, null: false
      add :received_at, :utc_datetime, null: false
    end

    create unique_index(:delivery_actual_events, [:source, :event_id])
    create index(:delivery_actual_events, [:order_id])
  end
end
