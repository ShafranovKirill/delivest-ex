defmodule Delivest.Net.Branches do
  import Ecto.Query
  alias Delivest.{Repo, Identity}
  alias Delivest.Net.Branch

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

  def get_branch(id) do
    case Cachex.get(:branch_cache, id) do
      {:ok, nil} -> fetch_from_db_and_cache(id)
      {:ok, %Branch{} = branch} -> {:ok, branch}
      _ -> {:error, :not_found}
    end
  end

  defp fetch_from_db_and_cache(id) do
    case Repo.get(Branch, id) do
      nil ->
        {:error, :not_found}

      branch ->
        cache_branch(id, branch)
        {:ok, branch}
    end
  end

  defp cache_branch(id, branch) do
    Cachex.put(:branch_cache, id, branch, ttl: :timer.minutes(30))
  end
end
