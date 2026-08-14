defmodule Delivest.Net.Branches do
  alias Delivest.{Repo}
  alias Delivest.Net.Branch

  def get_branch(id) do
    case Cachex.get(:branch_cache, id) do
      {:ok, nil} -> fetch_from_db_and_cache(id)
      {:ok, %Branch{} = branch} -> {:ok, branch}
      _ -> {:error, :not_found}
    end
  end

  def fetch_from_db_and_cache(id) do
    case Repo.get(Branch, id) do
      nil ->
        {:error, :not_found}

      branch ->
        {:ok, branch}
    end
  end
end
