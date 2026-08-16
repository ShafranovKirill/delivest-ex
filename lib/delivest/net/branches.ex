defmodule Delivest.Net.Branches do
  import Ecto.Query
  alias Delivest.Net.BranchInfo
  alias Delivest.{Repo, Identity}
  alias Delivest.Net.Branch

  @spec list_branch(Delivest.Identity.Staff.t()) :: Ecto.Query.t()
  def list_branch(staff) do
    permissions = staff.role.permissions || []

    cond do
      "admin" in permissions ->
        Branch

      Identity.can?(staff, "branch.read") ->
        branch_ids =
          Enum.map(staff.branches, & &1.id)

        Branch
        |> where([b], b.id in ^branch_ids)

      true ->
        Branch
        |> where([_b], false)
    end
  end

  @spec get_branch(binary()) :: {:ok, Branch.t()} | {:error, :not_found}
  def get_branch(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    case Cachex.get(:branch_cache, id) do
      {:ok, nil} -> fetch_from_db_and_cache(id, opts)
      {:ok, %Branch{} = branch} -> ensure_preloaded_and_cached(branch, preloads, id, opts)
      _ -> {:error, :not_found}
    end
  end

  def update_branch(%Branch{} = branch, branch_attrs, info_attrs) do
    branch = Repo.preload(branch, :info)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:branch, Branch.changeset(branch, branch_attrs))
    |> Ecto.Multi.run(:info, fn repo, _changes -> upsert_branch_info(repo, branch, info_attrs) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{branch: updated_branch, info: updates_info}} ->
        Cachex.del(:branch_cache, updated_branch.id)

        {:ok, %{updated_branch | info: updates_info}}

      {:error, failed_operation, changeset, _changes} ->
        {:error, failed_operation, changeset}
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

  @spec create_branch(Delivest.Identity.Staff.t(), map()) ::
          {:ok, Branch.t()} | {:error, Ecto.Changeset.t() | :forbidden}
  def create_branch(staff, attrs) do
    if Identity.can?(staff, "branch.create") do
      %Branch{}
      |> Branch.changeset(attrs)
      |> Repo.insert()
    else
      {:error, :forbidden}
    end
  end

  @spec soft_delete_branch(Delivest.Identity.Staff.t(), Branch.t()) ::
          {:ok, Branch.t()} | {:error, Ecto.Changeset.t() | :forbidden}
  def soft_delete_branch(staff, %Branch{} = branch) do
    if Identity.can?(staff, "branch.delete") do
      branch
      |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now(:second)})
      |> Repo.update()
      |> case do
        {:ok, deleted_branch} ->
          Cachex.del(:branch_cache, deleted_branch.id)
          {:ok, deleted_branch}

        error ->
          error
      end
    else
      {:error, :forbidden}
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
    Cachex.put(:branch_cache, id, branch, ttl: :timer.minutes(30))
  end
end
