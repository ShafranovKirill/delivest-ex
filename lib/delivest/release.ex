defmodule Delivest.Release do
  @app :delivest

  alias Delivest.Repo
  alias Delivest.Identity.{Staff, Staffs, Role}

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def create_admin(login, password) do
    load_app()

    Ecto.Migrator.with_repo(Repo, fn _repo ->
      Repo.transaction(fn ->
        role = ensure_admin_role()
        insert_admin_staff(login, password, role.id)
      end)
    end)
  end

  defp ensure_admin_role do
    case Repo.get_by(Role, name: "admin") || Repo.get_by(Role, name: "Admin") do
      %Role{} = role ->
        role

      nil ->
        create_default_admin_role()
    end
  end

  defp create_default_admin_role do
    role_params = %{
      name: "Admin",
      permissions: ["admin"]
    }

    changeset = Role.changeset(%Role{}, role_params)

    case Repo.insert(changeset) do
      {:ok, role} ->
        IO.puts("Created 'Admin' role in DB (ID: #{role.id})")
        role

      {:error, changeset} ->
        IO.puts("Failed to create admin role:")
        IO.inspect(changeset.errors)
        Repo.rollback("failed to create admin role")
    end
  end

  defp insert_admin_staff(login, password, role_id) do
    case Repo.get_by(Staff, login: login) do
      nil ->
        params = %{
          login: login,
          password: password,
          role_id: role_id
        }

        case Staffs.system_create_staff(params) do
          {:ok, staff} ->
            IO.puts("Admin created: #{staff.login} (Role ID: #{role_id})")
            staff

          {:error, changeset} ->
            IO.puts("Failed to create admin staff:")
            IO.inspect(changeset.errors)
            Repo.rollback("failed to create admin staff")
        end

      _staff ->
        IO.puts("Admin staff '#{login}' already exists.")
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
