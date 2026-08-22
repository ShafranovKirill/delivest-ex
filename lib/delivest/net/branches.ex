defmodule Delivest.Net.Branches do
  import Ecto.Query
  alias Delivest.Net.{BranchInfo, Branch}
  alias Delivest.{Repo, Identity, Net}

  @spec list_branch_for_staff(Delivest.Identity.Staff.t(), keyword()) :: [Branch.t()]
  def list_branch_for_staff(staff, opts \\ []) do
    permissions = staff.role.permissions || []

    Branch
    |> where([b], is_nil(b.deleted_at))
    |> then(fn query ->
      cond do
        "admin" in permissions ->
          query

        true ->
          branch_ids = Enum.map(staff.branches || [], & &1.id)
          where(query, [b], b.id in ^branch_ids)
      end
    end)
    |> maybe_preload_query(opts[:preload])
    |> Repo.all()
  end

  def list_all_branch(opts \\ []) do
    Branch
    |> where([b], is_nil(b.deleted_at) and b.is_active == true)
    |> maybe_preload_query(opts[:preload])
    |> Repo.all()
  end

  defp maybe_preload_query(query, nil), do: query
  defp maybe_preload_query(query, preloads), do: preload(query, ^preloads)

  @spec get_branch(binary()) :: {:ok, Branch.t()} | {:error, :not_found}
  def get_branch(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    case Cachex.get(:branch_cache, id) do
      {:ok, nil} -> fetch_from_db_and_cache(id, opts)
      {:ok, %Branch{} = branch} -> ensure_preloaded_and_cached(branch, preloads, id, opts)
      _ -> {:error, :not_found}
    end
  end

  def update_branch(staff, %Branch{} = branch, branch_attrs, info_attrs) do
    if Identity.can?(staff, "branches.update") do
      branch = Repo.preload(branch, :info)

      Ecto.Multi.new()
      |> Ecto.Multi.update(:branch, Branch.changeset(branch, branch_attrs))
      |> Ecto.Multi.run(:info, fn repo, _changes ->
        upsert_branch_info(repo, branch, info_attrs)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{branch: updated_branch, info: updates_info}} ->
          Cachex.del(:branch_cache, updated_branch.id)

          {:ok, %{updated_branch | info: updates_info}}

        {:error, failed_operation, changeset, _changes} ->
          {:error, failed_operation, changeset}
      end
    else
      {:error, :forbidden}
    end
  end

  defp upsert_branch_info(repo, branch, attrs) do
    if branch.info do
      branch.info
      |> BranchInfo.changeset(attrs)
      |> repo.update()
    else
      Ecto.build_assoc(branch, :info)
      |> BranchInfo.changeset(attrs)
      |> repo.insert()
    end
  end

  def create_branch(staff, branch_attrs, info_attrs) do
    if Identity.can?(staff, "branch.create") do
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:branch, Branch.changeset(%Branch{}, branch_attrs))
      |> Ecto.Multi.insert(:branch_info, fn %{branch: branch} ->
        attrs = Map.put(info_attrs, "branch_id", branch.id)
        BranchInfo.changeset(%BranchInfo{}, attrs)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{branch: branch, branch_info: branch_info}} ->
          {:ok, %{branch | info: branch_info}}

        {:error, failed_operation, changeset, _changes} ->
          {:error, failed_operation, changeset}
      end
    else
      {:error, :forbidden}
    end
  end

  @spec soft_delete_branch(Delivest.Identity.Staff.t(), Branch.t()) ::
          {:ok, Branch.t()}
          | {:error, atom(), Ecto.Changeset.t() | term(), map()}
          | {:error, :forbidden}
  def soft_delete_branch(staff, %Branch{} = branch) do
    if Identity.can?(staff, "branch.delete") do
      Ecto.Multi.new()
      |> Ecto.Multi.delete_all(
        :delete_staff_branches,
        from(sb in "staff_branches", where: sb.branch_id == type(^branch.id, :binary_id))
      )
      |> Ecto.Multi.update(
        :soft_delete_branch,
        Ecto.Changeset.change(branch, %{deleted_at: DateTime.utc_now(:second)})
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{soft_delete_branch: deleted_branch}} ->
          Cachex.del(:branch_cache, deleted_branch.id)
          {:ok, deleted_branch}

        {:error, failed_operation, reason, changes} ->
          {:error, failed_operation, reason, changes}
      end
    else
      {:error, :forbidden}
    end
  end

  def get_menu_for_branch(branch_id) do
    case Cachex.get(:menu_cache, branch_id) do
      {:ok, nil} ->
        menu = Net.list_category_for_branch(branch_id, preload: [:products])

        Cachex.put(:menu_cache, branch_id, menu, ttl: :timer.hours(1))
        {:ok, menu}

      {:ok, menu} ->
        {:ok, menu}
    end
  end

  defp ensure_preloaded_and_cached(branch, preloads, id, opts) do
    if needs_preload?(branch, preloads) do
      branch = maybe_preload_branch(branch, opts)
      cache_branch(id, branch)
      {:ok, branch}
    else
      {:ok, branch}
    end
  end

  defp needs_preload?(branch, preloads) do
    Enum.any?(preloads, fn assoc ->
      match?(%Ecto.Association.NotLoaded{}, Map.get(branch, assoc))
    end)
  end

  defp maybe_preload_branch(branch, opts) do
    case Keyword.get(opts, :preload) do
      nil -> branch
      preloads -> Repo.preload(branch, preloads)
    end
  end

  defp fetch_from_db_and_cache(id, opts) do
    case Repo.get(Branch, id) do
      nil ->
        {:error, :not_found}

      branch ->
        branch = maybe_preload_branch(branch, opts)
        cache_branch(id, branch)
        {:ok, branch}
    end
  end

  @spec cache_branch(integer(), Branch.t()) ::
          {:commit, true} | {:commit, false} | {:error, term()}
  defp cache_branch(id, branch) do
    Cachex.put(:branch_cache, id, branch, ttl: :timer.hours(1))
  end
end
