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
end
