defmodule Mix.Tasks.Delivest.SeedRoles do
  use Mix.Task

  alias Delivest.Repo
  alias Delivest.Identity.Role
  import Ecto.Query

  @shortdoc "Seeds default system roles with predefined permissions"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    roles = [
      %{
        name: "admin",
        permissions: ["admin"]
      },
      %{
        name: "cashier",
        permissions: [
          "clients.create",
          "clients.read",
          "clients.update",
          "clients.delete",
          "orders.create",
          "orders.read",
          "orders.update",
          "orders.delete"
        ]
      },
      %{
        name: "catalog_manager",
        permissions: [
          "categories.create",
          "categories.read",
          "categories.update",
          "categories.delete",
          "products.create",
          "products.read",
          "products.update",
          "products.delete",
          "stocks.create",
          "stocks.read",
          "stocks.update",
          "stocks.delete",
          "orders.create",
          "orders.read",
          "orders.update",
          "orders.delete"
        ]
      },
      %{
        name: "manager",
        permissions: [
          "branches.create",
          "branches.read",
          "branches.update",
          "branches.delete",
          "categories.create",
          "categories.read",
          "categories.update",
          "categories.delete",
          "products.create",
          "products.read",
          "products.update",
          "products.delete",
          "stocks.create",
          "stocks.read",
          "stocks.update",
          "stocks.delete",
          "orders.create",
          "orders.read",
          "orders.update",
          "orders.delete",
          "clients.create",
          "clients.read",
          "clients.update",
          "clients.delete"
        ]
      },
      %{
        name: "director",
        permissions: [
          "staff.create",
          "staff.read",
          "staff.update",
          "staff.delete",
          "roles.create",
          "roles.read",
          "roles.update",
          "roles.delete",
          "branches.create",
          "branches.read",
          "branches.update",
          "branches.delete",
          "categories.create",
          "categories.read",
          "categories.update",
          "categories.delete",
          "products.create",
          "products.read",
          "products.update",
          "products.delete",
          "stocks.create",
          "stocks.read",
          "stocks.update",
          "stocks.delete",
          "clients.create",
          "clients.read",
          "clients.update",
          "clients.delete"
        ]
      }
    ]

    Enum.each(roles, &upsert_role/1)
    Mix.shell().info("Roles seeding completed.")
  end

  defp upsert_role(%{name: name, permissions: permissions} = _attrs) do
    existing_role =
      Repo.one(from r in Role, where: fragment("lower(?) = lower(?)", r.name, ^name))

    case existing_role do
      nil ->
        %Role{}
        |> Role.changeset(%{name: name, permissions: permissions})
        |> Repo.insert()

        case_result_create(name)

      role ->
        role
        |> Role.changeset(%{permissions: permissions})
        |> Repo.update()

        case_result_update(name)
    end
  end

  defp case_result_create(name) do
    Mix.shell().info("-> Created role: #{name}")
  end

  defp case_result_update(name) do
    Mix.shell().info("-> Updated role: #{name}")
  end
end
