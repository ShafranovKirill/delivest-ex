defmodule Delivest.Identity.Acl do
  import Ecto.Query

  def can?(nil, _permission), do: false

  def can?(staff, permission) do
    cond do
      "admin" in staff.role.permissions ->
        true

      permission in staff.role.permissions ->
        true

      true ->
        false
    end
  end

  def can_any?(nil, _permissions), do: false

  def can_any?(staff, permissions) when is_list(permissions) do
    if "admin" in staff.role.permissions do
      true
    else
      Enum.any?(permissions, &(&1 in staff.role.permissions))
    end
  end

  def has_branch_access?(nil, _branch_id), do: false

  def has_branch_access?(staff, branch_id) do
    staff =
      if Ecto.assoc_loaded?(staff.branches) do
        staff
      else
        Delivest.Repo.preload(staff, :branches)
      end

    cond do
      "admin" in staff.role.permissions ->
        true

      true ->
        Enum.any?(staff.branches || [], &(&1.id == branch_id))
    end
  end

  defp get_branch_ids(%{branches: branches}) when is_list(branches) do
    Enum.map(branches, & &1.id)
  end

  defp get_branch_ids(_), do: []

  @spec scope_by_branch(Ecto.Queryable.t(), Delivest.Identity.Staff.t(), String.t()) ::
          Ecto.Query.t()
  def scope_by_branch(query, staff, permission) do
    cond do
      not can?(staff, permission) ->
        where(query, [q], false)

      can?(staff, "admin") ->
        query

      true ->
        {join_table, foreign_key} = extract_join_info(query)
        branch_ids = get_branch_ids(staff)

        if branch_ids == [] do
          where(query, [q], false)
        else
          query
          |> join(:inner, [q], j in ^join_table, on: field(j, ^foreign_key) == q.id)
          |> where([q, j], j.branch_id in ^branch_ids)
          |> distinct([q, j], q.id)
        end
    end
  end

  defp extract_join_info(%Ecto.Query{from: %{source: {_, model}}}), do: extract_join_info(model)
  defp extract_join_info(Delivest.Net.Category), do: {"categories_branches", :category_id}
  defp extract_join_info(Delivest.Net.Product), do: {"products_branches", :product_id}
  defp extract_join_info(Delivest.Identity.Staff), do: {"staff_branches", :staff_id}
end
