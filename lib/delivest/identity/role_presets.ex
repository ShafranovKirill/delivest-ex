defmodule Delivest.Identity.RolePresets do
  import Ecto.Query

  alias Delivest.Identity.{Acl, Definitions, Role}
  alias Delivest.Repo

  @admin "Администратор"

  @operator ~w(
    orders.create orders.read orders.update
    clients.create clients.read clients.update
    categories.read products.read stops.update
    pos.use
  )

  @kitchen ~w(orders.read orders.cook)

  @cashier ~w(orders.read pos.use)

  @courier ~w(orders.deliver)

  @analyst ~w(orders.read clients.read statistics.read finance.read branches.read)

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
                      finance.read
                      statistics.read staff.read
                      segments.read segments.manage
                    )

  @franchise_manager Enum.uniq(
                       @branch_manager ++
                         @catalog ++
                         ~w(staff.create staff.update roles.read branches.create orders.revert
                            orders.cook orders.deliver clients.read segments.network)
                     )

  @accountant ~w(branches.read orders.read statistics.read finance.read finance.receipts_retry finance.receipts_refund)

  def all do
    [
      %{name: @admin, permissions: [Definitions.admin()]},
      %{name: "Управляющий франшизой", permissions: @franchise_manager},
      %{name: "Менеджер филиала", permissions: @branch_manager},
      %{name: "Оператор", permissions: @operator},
      %{name: "Кассир", permissions: @cashier},
      %{name: "Кухня", permissions: @kitchen},
      %{name: "Курьер", permissions: @courier},
      %{name: "Аналитик", permissions: @analyst},
      %{name: "Бухгалтер", permissions: @accountant},
      %{name: "Контент-менеджер", permissions: @catalog}
    ]
  end

  def admin_role do
    Repo.one(
      from r in Role,
        where: fragment("? @> ?::jsonb", r.permissions, ^[Definitions.admin()]),
        limit: 1
    )
  end

  def ensure_admin_role do
    case admin_role() do
      %Role{} = role -> {:ok, role}
      nil -> %Role{} |> Role.changeset(hd(all())) |> Repo.insert()
    end
  end

  def seed(staff) do
    if Acl.can?(staff, Definitions.admin()), do: seed_missing(), else: {:error, :forbidden}
  end

  def seed do
    {:ok, roles} = seed_missing()
    roles
  end

  defp seed_missing do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["delivest_role_presets"])
      Enum.map(all(), &seed_one/1)
    end)
  end

  defp seed_one(%{name: name} = preset) do
    if exists?(preset) do
      {:exists, name}
    else
      case %Role{} |> Role.changeset(preset) |> Repo.insert(mode: :savepoint) do
        {:ok, _role} ->
          {:created, name}

        {:error, changeset} ->
          if exists?(preset), do: {:exists, name}, else: Repo.rollback(changeset)
      end
    end
  end

  defp exists?(%{permissions: ["admin"]}), do: admin_role() != nil

  defp exists?(%{name: name}),
    do: Repo.exists?(from r in Role, where: fragment("lower(?) = lower(?)", r.name, ^name))
end
