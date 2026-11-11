defmodule Delivest.Repo.Migrations.FunnelReceiptAsofIndexes do
  use Ecto.Migration

  def change do
    create index(:funnel_events, [:session_id, :received_at, :id])
  end
end
