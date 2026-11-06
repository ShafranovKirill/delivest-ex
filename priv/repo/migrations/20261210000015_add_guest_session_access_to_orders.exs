defmodule Delivest.Repo.Migrations.AddGuestSessionAccessToOrders do
  use Ecto.Migration

  @moduledoc """
  Only legacy orders without a linked client can safely regain session access.
  Older guest orders linked by phone remain available through that client's login,
  since the old schema cannot distinguish them from authenticated orders.

  Rolling this migration back also requires rolling back the ownership code;
  that old code allows a new account on the same session to access prior orders.
  """

  def up do
    alter table(:orders) do
      add :guest_session_access, :boolean, null: false, default: false
    end

    execute("""
    UPDATE orders
    SET guest_session_access = true
    WHERE client_id IS NULL AND session_id IS NOT NULL
    """)
  end

  def down do
    alter table(:orders) do
      remove :guest_session_access
    end
  end
end
