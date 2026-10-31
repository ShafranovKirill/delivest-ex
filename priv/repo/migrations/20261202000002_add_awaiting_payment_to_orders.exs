defmodule Delivest.Repo.Migrations.AddAwaitingPaymentToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :awaiting_payment, :boolean, default: false, null: false
    end

    create index(:orders, [:inserted_at],
             where: "awaiting_payment",
             name: :orders_awaiting_payment_index
           )
  end
end
