defmodule Delivest.Repo.Migrations.SplitBranchPermissions do
  use Ecto.Migration

  @grants [
    {"branches.read", ["delivery.read", "integrations.read"]},
    {"branches.update", ["delivery.update", "integrations.update"]},
    {"products.update", ["stops.update"]}
  ]

  @operator ~w(
    orders.create orders.read orders.update
    clients.create clients.read clients.update
    categories.read products.read stops.update
  )

  @catalog ~w(
    categories.create categories.read categories.update categories.delete
    products.create products.read products.update products.delete
    stops.update
    stocks.create stocks.read stocks.update stocks.delete
    promotions.create promotions.read promotions.update promotions.delete
  )

  @branch_manager @operator ++
                    ~w(
                      branches.read branches.update
                      stocks.read promotions.read
                      delivery.read delivery.update
                      integrations.read
                      statistics.read staff.read
                    )

  @director ~w(
    staff.create staff.read staff.update staff.delete
    roles.create roles.read roles.update roles.delete
    branches.create branches.read branches.update branches.delete
    categories.create categories.read categories.update categories.delete
    products.create products.read products.update products.delete
    stops.update
    stocks.create stocks.read stocks.update stocks.delete
    promotions.create promotions.read promotions.update promotions.delete
    clients.create clients.read clients.update clients.delete
    orders.create orders.read orders.update orders.delete
    delivery.read delivery.update
    integrations.read integrations.update
    franchise.update
    statistics.read
    logs.read
  )

  @presets [
    {"admin", "Администратор", ["admin"]},
    {"director", "Управляющий", @director},
    {"manager", "Менеджер филиала", @branch_manager},
    {"cashier", "Оператор", @operator},
    {"catalog_manager", "Контент-менеджер", @catalog}
  ]

  def up do
    Enum.each(@grants, fn {source, added} ->
      execute("""
      UPDATE roles
      SET permissions = (
        SELECT jsonb_agg(DISTINCT permission)
        FROM jsonb_array_elements_text(permissions || '#{Jason.encode!(added)}'::jsonb) permission
      )
      WHERE permissions @> '#{Jason.encode!([source])}'::jsonb
      """)
    end)

    Enum.each(@presets, fn {old, new, permissions} ->
      execute("""
      UPDATE roles
      SET name = '#{new}', permissions = '#{Jason.encode!(permissions)}'::jsonb
      WHERE lower(name) = '#{old}'
        AND NOT EXISTS (SELECT 1 FROM roles WHERE name = '#{new}')
      """)
    end)
  end

  def down, do: :ok
end
