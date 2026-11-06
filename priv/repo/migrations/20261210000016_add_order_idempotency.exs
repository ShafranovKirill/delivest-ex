defmodule Delivest.Repo.Migrations.AddOrderIdempotency do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :idempotency_owner, :string
      add :idempotency_key, :uuid
      add :idempotency_fingerprint, :string
    end

    create unique_index(:orders, [:idempotency_owner, :branch_id, :idempotency_key],
             name: :orders_idempotency_owner_branch_key_index,
             where: "idempotency_key IS NOT NULL"
           )

    create constraint(:orders, :orders_idempotency_all_or_none,
             check:
               "(idempotency_owner IS NULL AND idempotency_key IS NULL AND idempotency_fingerprint IS NULL) OR (idempotency_owner IS NOT NULL AND idempotency_key IS NOT NULL AND idempotency_fingerprint IS NOT NULL)"
           )
  end
end
