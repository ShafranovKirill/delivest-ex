defmodule Delivest.Identity.Staffs do
  import Ecto.Query
  alias Delivest.Repo
  alias Delivest.Identity.{Staff, Acl}

  @spec list_staff(map(), map(), keyword()) ::
          {:ok, {[Staff.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_staff(staff, params \\ %{}, opts \\ []) do
    base_query =
      Staff
      |> where([a], is_nil(a.deleted_at))
      |> Acl.scope_query(staff, "staff.read")

    query =
      if preloads = Keyword.get(opts, :preload) do
        preload(base_query, ^preloads)
      else
        base_query
      end

    Flop.validate_and_run(query, params, for: Staff)
  end

  @spec create_staff(Staff.t(), map()) ::
          {:ok, Staff.t()} | {:error, :forbidden} | {:error, Ecto.Changeset.t()}
  def create_staff(staff, attrs) do
    if Acl.can?(staff, "staff.create") do
      %Staff{}
      |> Staff.changeset(attrs)
      |> Repo.insert()
    else
      {:error, :forbidden}
    end
  end

  @spec update_staff(
          Staff.t(),
          Staff.t(),
          map()
        ) :: {:ok, Staff.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}

  def update_staff(staff, %Staff{} = updatable_staff, attrs) do
    if(Acl.can?(staff, "staff.update")) do
      updatable_staff
      |> Staff.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, updated_staff} ->
          Cachex.del(:staff_cache, updatable_staff.id)

          Phoenix.PubSub.broadcast(
            Delivest.PubSub,
            "staff_updates:#{updated_staff.id}",
            :staff_updated
          )

          {:ok, updated_staff}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :forbidden}
    end
  end

  @spec change_password(Staff.t(), Staff.t(), map()) ::
          {:ok, Staff.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :forbidden}
  def change_password(staff, %Staff{} = updatable_staff, attrs) do
    if Acl.can?(staff, "admin") do
      with {:ok, updated_staff} <-
             updatable_staff |> Staff.password_changeset(attrs) |> Repo.update() do
        Cachex.del(:staff_cache, updated_staff.id)
        {:ok, updated_staff}
      end
    else
      {:error, :forbidden}
    end
  end

  @spec get_staff(String.t(), keyword()) :: {:error, :not_found} | {:ok, nil} | {:ok, Staff.t()}
  def get_staff(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    case Cachex.get(:staff_cache, id) do
      {:ok, nil} ->
        fetch_from_db_and_cache(id, opts)

      {:ok, %Staff{} = staff} ->
        ensure_preloaded_and_cached(staff, preloads, id, opts)

      _ ->
        {:error, :not_found}
    end
  end

  @spec get_staff_by_login(String.t()) :: {:ok, Staff.t()} | {:error, :not_found}
  def get_staff_by_login(login) do
    case Repo.get_by(Staff, login: login) do
      nil -> {:error, :not_found}
      staff -> {:ok, staff}
    end
  end

  @spec soft_delete_staff(Staff.t(), Staff.t()) ::
          {:ok, Staff.t()} | {:error, :forbidden} | {:error, Ecto.Changeset.t()}
  def soft_delete_staff(staff, %Staff{} = removable_staff) do
    if Acl.can?(staff, "staff.delete") do
      with {:ok, deleted_staff} <-
             removable_staff
             |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now(:second)})
             |> Repo.update() do
        Cachex.del(:staff_cache, deleted_staff.id)
        {:ok, deleted_staff}
      end
    else
      {:error, :forbidden}
    end
  end

  @spec authenticate(any(), any()) ::
          {:error, :invalid_credentials} | {:ok, Staff.t()}
  def authenticate(login, password) do
    staff = Repo.get_by(Staff, login: login)

    if staff do
      valid_pass? = Argon2.verify_pass(password, staff.password_hash)

      cond do
        valid_pass? ->
          {:ok, staff}

        true ->
          {:error, :invalid_credentials}
      end
    else
      Argon2.no_user_verify()
      {:error, :invalid_credentials}
    end
  end

  @spec system_create_staff(map()) :: {:ok, Staff.t()} | {:error, Ecto.Changeset.t()}
  def system_create_staff(attrs) do
    %Staff{}
    |> Staff.changeset(attrs)
    |> Repo.insert()
  end

  defp fetch_from_db_and_cache(id, opts) do
    case Repo.get(Staff, id) do
      nil ->
        {:error, :not_found}

      staff ->
        staff = maybe_preload_staff(staff, opts)
        cache_staff(id, staff)
        {:ok, staff}
    end
  end

  defp cache_staff(id, staff) do
    Cachex.put(:staff_cache, id, staff, ttl: :timer.minutes(5))
  end

  defp maybe_preload_staff(staff, opts) do
    case Keyword.get(opts, :preload) do
      nil -> staff
      preloads -> Repo.preload(staff, preloads)
    end
  end

  defp ensure_preloaded_and_cached(staff, preloads, id, opts) do
    if needs_preload?(staff, preloads) do
      staff = maybe_preload_staff(staff, opts)
      cache_staff(id, staff)
      {:ok, staff}
    else
      {:ok, staff}
    end
  end

  defp needs_preload?(staff, preloads) do
    Enum.any?(preloads, fn assoc ->
      match?(%Ecto.Association.NotLoaded{}, Map.get(staff, assoc))
    end)
  end
end
