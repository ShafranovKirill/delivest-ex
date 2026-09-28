defmodule Delivest.Release do
  @app :delivest

  alias Delivest.Repo
  alias Delivest.Identity.{Staff, Staffs, Role}
  import Ecto.Query

  @public_bucket "delivest"
  @private_bucket "delivest-private"
  @default_buckets [@public_bucket, @private_bucket]

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

  def create_admin(login \\ "admin123", password \\ "AdminSecret123!") do
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

  def seed_roles do
    load_app()

    Ecto.Migrator.with_repo(Repo, fn _repo ->
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
      IO.puts("Roles seeding completed.")
    end)
  end

  defp upsert_role(%{name: name, permissions: permissions}) do
    existing_role =
      Repo.one(from(r in Role, where: fragment("lower(?) = lower(?)", r.name, ^name)))

    case existing_role do
      nil ->
        %Role{}
        |> Role.changeset(%{name: name, permissions: permissions})
        |> Repo.insert()

        IO.puts("-> Created role: #{name}")

      role ->
        role
        |> Role.changeset(%{permissions: permissions})
        |> Repo.update()

        IO.puts("-> Updated role: #{name}")
    end
  end

  def storage_setup do
    load_app()

    Application.ensure_all_started(:ex_aws)

    buckets = Application.get_env(:delivest, Delivest.Storage)[:buckets] || @default_buckets
    IO.puts("[Storage.Setup] Starting storage setup. Target buckets: #{inspect(buckets)}")

    Enum.each(buckets, &setup_bucket/1)
    IO.puts("[Storage.Setup] Storage setup completed.")
  end

  defp setup_bucket(bucket) do
    IO.puts("[Storage.Setup] Ensuring bucket '#{bucket}' exists...")

    case ExAws.S3.put_bucket(bucket, "") |> ExAws.request() do
      {:ok, _response} ->
        IO.puts("[Storage.Setup] Bucket '#{bucket}' successfully created.")
        configure_bucket_policy(bucket)

      {:error, error} ->
        error_str = inspect(error)

        if String.contains?(error_str, "BucketAlreadyOwnedByYou") or
             String.contains?(error_str, "BucketAlreadyExists") or
             String.contains?(error_str, "409") do
          IO.puts("[Storage.Setup] Bucket '#{bucket}' already exists.")
          configure_bucket_policy(bucket)
        else
          IO.puts("[Storage.Setup] Error creating bucket '#{bucket}': #{error_str}")
        end
    end
  end

  defp configure_bucket_policy(@public_bucket = bucket) do
    IO.puts("[Storage.Setup] Applying public read policy to '#{bucket}/*'...")

    policy = %{
      "Version" => "2012-10-17",
      "Statement" => [
        %{
          "Sid" => "PublicReadGetObject",
          "Effect" => "Allow",
          "Principal" => "*",
          "Action" => ["s3:GetObject"],
          "Resource" => ["arn:aws:s3:::#{bucket}/*"]
        }
      ]
    }

    policy_json = Jason.encode!(policy)

    case ExAws.S3.put_bucket_policy(bucket, policy_json) |> ExAws.request() do
      {:ok, _response} ->
        IO.puts("[Storage.Setup] Public policy successfully applied to '#{bucket}'.")

      {:error, error} ->
        IO.puts("[Storage.Setup] Failed to apply policy to '#{bucket}': #{inspect(error)}")
    end
  end

  defp configure_bucket_policy(bucket) do
    IO.puts("[Storage.Setup] Bucket '#{bucket}' is configured as private. Skipping policy.")
  end

  def setup do
    migrate()
    storage_setup()
    seed_roles()
    create_admin()
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)

    for app <- [:logger, :jason, :ecto, :ecto_sql, :postgrex, :ex_aws, :ex_aws_s3] do
      Application.ensure_all_started(app)
    end

    {:ok, _} = Repo.start_link()
  end
end
