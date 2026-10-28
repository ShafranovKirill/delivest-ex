defmodule Delivest.Identity.Staffs do
  import Ecto.Query
  alias Delivest.Repo
  alias Delivest.Identity.Branch
  alias Delivest.Identity.{Staff, Acl, Delegation}
  alias Delivest.Audit

  @spec list_staff(Delivest.Identity.Staff.t(), map(), keyword()) ::
          {:ok, {[Staff.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()} | {:error, :forbidden}
  def list_staff(staff, params \\ %{}, opts \\ []) do
    if Acl.can?(staff, "staff.read") do
      Staff
      |> where([a], is_nil(a.deleted_at))
      |> then(fn query ->
        if Acl.can?(staff, "admin") do
          query
        else
          branch_ids = Enum.map(staff.branches || [], & &1.id)

          query
          |> join(:inner, [s], sb in "staff_branches", on: sb.staff_id == s.id)
          |> where([s, sb], sb.branch_id in type(^branch_ids, {:array, Ecto.UUID}))
          |> distinct([s], s.id)
        end
      end)
      |> maybe_preload_query(opts)
      |> Flop.validate_and_run(params, for: Staff)
    else
      {:error, :forbidden}
    end
  end

  @spec create_staff(Staff.t(), map()) ::
          {:ok, Staff.t()} | {:error, :forbidden} | {:error, Ecto.Changeset.t()}
  def create_staff(staff, attrs) do
    staff
    |> do_create_staff(attrs)
    |> Audit.track(staff, "staff.created")
  end

  defp do_create_staff(staff, attrs) do
    if Acl.can?(staff, "staff.create") and Delegation.assignment?(staff, attrs) do
      insert_staff_with_branches(attrs)
    else
      {:error, :forbidden}
    end
  end

  defp insert_staff_with_branches(attrs) do
    %Staff{}
    |> Staff.changeset(attrs)
    |> put_branches(attrs)
    |> Repo.insert()
    |> case do
      {:ok, created_staff} ->
        {:ok, Repo.preload(created_staff, :branches)}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @spec update_staff(
          Staff.t(),
          Staff.t(),
          map()
        ) :: {:ok, Staff.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}

  def update_staff(staff, %Staff{} = updatable_staff, attrs) do
    staff
    |> do_update_staff(updatable_staff, attrs)
    |> Audit.track(staff, "staff.updated")
  end

  defp do_update_staff(staff, %Staff{} = updatable_staff, attrs) do
    if Acl.can?(staff, "staff.update") and Delegation.staff?(staff, updatable_staff) and
         Delegation.assignment?(staff, attrs, updatable_staff) do
      updatable_staff
      |> Repo.preload(:branches)
      |> Staff.changeset(attrs)
      |> put_branches(attrs)
      |> Repo.update()
      |> case do
        {:ok, updated_staff} ->
          Cachex.del(:staff_cache, updatable_staff.id)

          Phoenix.PubSub.broadcast(
            Delivest.PubSub,
            "staff_updates:#{updated_staff.id}",
            :staff_updated
          )

          {:ok, Repo.preload(updated_staff, :branches, force: true)}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :forbidden}
    end
  end

  defp put_branches(changeset, attrs) do
    branch_ids = attrs["branch_ids"] || attrs[:branch_ids]

    case branch_ids do
      nil ->
        changeset

      branch_ids ->
        branches = Repo.all(from b in Branch, where: b.id in ^branch_ids)
        Ecto.Changeset.put_assoc(changeset, :branches, branches)
    end
  end

  @spec change_password(Staff.t(), Staff.t(), map()) ::
          {:ok, Staff.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :forbidden}
  def change_password(staff, %Staff{} = updatable_staff, attrs) do
    staff
    |> do_change_password(updatable_staff, attrs)
    |> Audit.track(staff, "staff.password_changed")
  end

  defp do_change_password(staff, %Staff{} = updatable_staff, attrs) do
    if Delegation.password?(staff, updatable_staff) do
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
    case Repo.one(from s in active(), where: s.login == ^login) do
      nil -> {:error, :not_found}
      staff -> {:ok, staff}
    end
  end

  @spec soft_delete_staff(Staff.t(), Staff.t()) ::
          {:ok, Staff.t()} | {:error, :forbidden} | {:error, Ecto.Changeset.t()}
  def soft_delete_staff(staff, %Staff{} = removable_staff) do
    staff
    |> do_soft_delete_staff(removable_staff)
    |> Audit.track(staff, "staff.deleted")
  end

  defp do_soft_delete_staff(staff, %Staff{} = removable_staff) do
    if Acl.can?(staff, "staff.delete") and staff.id != removable_staff.id and
         Delegation.staff?(staff, removable_staff) do
      with {:ok, deleted_staff} <-
             removable_staff
             |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now(:second)})
             |> Repo.update() do
        Cachex.del(:staff_cache, deleted_staff.id)

        Phoenix.PubSub.broadcast(
          Delivest.PubSub,
          "staff_updates:#{deleted_staff.id}",
          :staff_updated
        )

        {:ok, deleted_staff}
      end
    else
      {:error, :forbidden}
    end
  end

  @spec authenticate(any(), any()) ::
          {:error, :invalid_credentials} | {:ok, Staff.t()}
  def authenticate(login, password) do
    staff = Repo.one(from s in active(), where: s.login == ^login)

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
    insert_staff_with_branches(attrs)
  end

  defp fetch_from_db_and_cache(id, opts) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Staff{} = staff <- Repo.one(from s in active(), where: s.id == ^uuid) do
      staff = maybe_preload_staff(staff, opts)
      cache_staff(id, staff)
      {:ok, staff}
    else
      _ -> {:error, :not_found}
    end
  end

  defp active, do: from(s in Staff, where: is_nil(s.deleted_at))

  defp cache_staff(id, staff) do
    Cachex.put(:staff_cache, id, staff, ttl: :timer.minutes(5))
  end

  defp maybe_preload_staff(staff, opts) do
    case Keyword.get(opts, :preload) do
      nil -> staff
      preloads -> Repo.preload(staff, preloads)
    end
  end

  defp maybe_preload_query(query, opts) do
    case Keyword.get(opts, :preload) do
      nil -> query
      preloads -> preload(query, ^preloads)
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
