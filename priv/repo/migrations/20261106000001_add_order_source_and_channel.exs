defmodule Delivest.Repo.Migrations.AddOrderSourceAndChannel do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :source, :string, null: false, default: "app"
      add :channel, :map
    end

    execute "UPDATE orders SET source = 'staff' WHERE staff_id IS NOT NULL", ""

    create unique_index(:orders, ["(channel->>'provider')", "(channel->>'external_id')"],
             name: :orders_channel_external_id_index,
             where: "channel IS NOT NULL"
           )

    alter table(:branch_info) do
      add :channels, :map
    end
  end
end
