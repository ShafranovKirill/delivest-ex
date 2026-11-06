defmodule Delivest.Net.SharedOwnership do
  @moduledoc "Authorization for records linked to more than one branch."

  alias Delivest.{Identity, Relations, Repo}

  def branches(type, id), do: Relations.list_source_ids(type, id, "Branch") |> Enum.uniq()

  def authorize(staff, permission, type, id) do
    case branches(type, id) do
      [] ->
        if Identity.can?(staff, "admin"), do: :ok, else: {:error, :forbidden}

      branch_ids ->
        if Enum.all?(branch_ids, &(Identity.authorize(staff, permission, &1) == :ok)),
          do: :ok,
          else: {:error, :forbidden}
    end
  end

  def write(branch_ids, fun) when is_list(branch_ids) and is_function(fun, 0) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} ->
          Delivest.Net.Catalogs.bump_versions(branch_ids)
          value

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def write(:all, fun) when is_function(fun, 0) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} ->
          Delivest.Net.Catalogs.bump_all_versions()
          value

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end
end
