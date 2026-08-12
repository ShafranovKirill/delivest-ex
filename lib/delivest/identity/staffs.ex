defmodule Delivest.Identity.Staffs do
  import Ecto.Query
  alias Delivest.{Identity, Repo}
  alias Delivest.Identity.{Staff, Acl}

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

  def create_staff(staff, attrs) do
    if Acl.can?(staff, "staff.create") do
      %Staff{}
      |> Staff.changeset(attrs)
      |> Repo.insert()
    else
      {:error, :unauthorized}
    end
  end

  def update_staff(staff, %Staff{} = updatable_staff, attrs) do
    if(Acl.can?(staff, "staff.update")) do
      updatable_staff
      |> Staff.changeset(attrs)
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

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

  def soft_delete_staff(%Staff{} = staff) do
    staff
    |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now(:second)})
    |> Repo.update()
    |> case do
      {:ok, deleted_staff} ->
        Cachex.del(:staff_cache, deleted_staff.id)
        {:ok, deleted_staff}

      error ->
        error
    end
  end

  def authenticate(login, password) do
    staff = Repo.get_by(Staff, login: login)

    if staff do
      valid_pass? = Argon2.verify_pass(password, staff.password_hash)

      cond do
        staff.status in [:blocked] ->
          {:error, :staff_blocked}

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
