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

  def scope_query(query, nil, _permission), do: where(query, [q], false)

  def scope_query(query, staff, permission) do
    if can?(staff, permission) do
      query
    else
      where(query, [q], false)
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

  def scope_by_branch(query, staff, permission) do
    cond do
      not can?(staff, permission) ->
        where(query, [q], false)

      "admin" in staff.role.permissions ->
        query

      true ->
        branch_ids =
          case Map.get(staff, :branches) do
            nil -> []
            branches -> Enum.map(branches, & &1.id)
          end

        where(query, [q], q.branch_id in ^branch_ids)
    end
  end
end
