defmodule Delivest.Identity.AdminSeeder do
  require Logger

  alias Delivest.Repo
  alias Delivest.Identity.{Staff, Staffs, Role}

  def run do
    admin_login = Application.get_env(:delivest, :admin_login, "admin123")
    admin_pass = Application.get_env(:delivest, :admin_password, "AdminSecret123!")

    admin_role = get_or_create_admin_role()

    case Repo.get_by(Staff, login: admin_login) do
      nil ->
        params = %{
          login: admin_login,
          password: admin_pass,
          role_id: admin_role.id
        }

        case Staffs.system_create_staff(params) do
          {:ok, staff} ->
            Logger.info("Admin created automatically: #{staff.login} (Role ID: #{admin_role.id})")

          {:error, changeset} ->
            Logger.error(
              "Failed to create admin staff automatically: #{inspect(changeset.errors)}"
            )
        end

      _staff ->
        :ok
    end
  end

  defp get_or_create_admin_role do
    case Repo.get_by(Role, name: "admin") || Repo.get_by(Role, name: "Admin") do
      %Role{} = role ->
        role

      nil ->
        role_params = %{
          name: "Admin",
          permissions: ["admin"]
        }

        changeset = Role.changeset(%Role{}, role_params)

        case Repo.insert(changeset) do
          {:ok, role} ->
            Logger.info("Created 'admin' role in DB automatically (ID: #{role.id})")
            role

          {:error, changeset} ->
            Logger.error("Failed to create 'admin' role: #{inspect(changeset.errors)}")
            raise "Cannot proceed without admin role"
        end
    end
  end
end
