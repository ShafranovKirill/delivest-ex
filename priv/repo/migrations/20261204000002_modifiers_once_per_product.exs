defmodule Delivest.Repo.Migrations.ModifiersOncePerProduct do
  use Ecto.Migration

  def up, do: execute("UPDATE modifiers SET max_quantity = 1 WHERE max_quantity <> 1")

  def down, do: :ok
end
