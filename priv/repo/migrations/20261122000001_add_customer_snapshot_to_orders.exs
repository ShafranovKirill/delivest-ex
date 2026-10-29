defmodule Delivest.Repo.Migrations.AddCustomerSnapshotToOrders do
  use Ecto.Migration

  def up do
    alter table(:orders) do
      add :customer_name, :string
      add :customer_phone, :string
      add :customer_phone_ext, :string
      add :customer_email, :string
      add :persons, :integer
    end

    execute """
    UPDATE orders o SET customer_name = c.name, customer_phone = c.phone
    FROM clients c WHERE o.client_id = c.id
    """

    execute """
    UPDATE orders SET
      customer_name = COALESCE(customer_name, channel->'details'->>'client_name'),
      customer_phone = COALESCE(customer_phone, channel->'details'->>'phone')
    WHERE channel IS NOT NULL
    """

    execute """
    UPDATE orders SET persons = (channel->'details'->'request'->>'persons')::integer
    WHERE channel->'details'->'request'->>'persons' ~ '^[0-9]+$'
    """
  end

  def down do
    alter table(:orders) do
      remove :customer_name
      remove :customer_phone
      remove :customer_phone_ext
      remove :customer_email
      remove :persons
    end
  end
end
