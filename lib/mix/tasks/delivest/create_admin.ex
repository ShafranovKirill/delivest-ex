defmodule Mix.Tasks.Delivest.CreateAdmin do
  use Mix.Task

  alias Delivest.Repo
  alias Delivest.Identity.{Staff, Staffs, Role}

  @shortdoc "Creates default admin role and staff if not exists"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    admin_login = Application.get_env(:delivest, :admin_login, "admin123")
    admin_pass = Application.get_env(:delivest, :admin_password, "AdminSecret123!")

    admin_role = get_or_create_admin_role()

    # 2. Проверяем, существует ли уже админ
    case Repo.get_by(Staff, login: admin_login) do
      nil ->
        params = %{
          login: admin_login,
          password: admin_pass,
          role_id: admin_role.id
        }

        case Staffs.system_create_staff(params) do
          {:ok, staff} ->
            Mix.shell().info("Admin created: #{staff.login} (Role ID: #{admin_role.id})")

          {:error, changeset} ->
            Mix.shell().error("Failed to create admin staff:")
            IO.inspect(changeset.errors)
        end

      _staff ->
        Mix.shell().info("Admin staff already exists.")
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
            Mix.shell().info("Created 'admin' role in DB (ID: #{role.id})")
            role

          {:error, changeset} ->
            Mix.shell().error("Failed to create 'admin' role:")
            IO.inspect(changeset.errors)
            raise "Cannot proceed without admin role"
        end
    end
  end
end
