defmodule Delivest.Repo.Migrations.MakeOrderNumberNonUnique do
  use Ecto.Migration

  # order_number_seq is a CYCLE sequence (A000..Z999): numbers are human-friendly
  # labels that repeat after 26 000 orders, so they cannot be globally unique.
  def change do
    drop unique_index(:orders, [:number])
    create index(:orders, [:number])
  end
end
