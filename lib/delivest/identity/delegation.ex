defmodule Delivest.Identity.Delegation do
  alias Delivest.Identity.{Acl, Definitions, Role, Staff}
  alias Delivest.Repo

  def admin?(actor), do: Acl.can?(actor, Definitions.admin())

  def admin_role?(%Role{permissions: permissions}), do: Definitions.admin() in permissions
  def admin_role?(_role), do: false

  def admin_staff?(%Staff{} = staff),
    do: staff |> Repo.preload(:role) |> Map.get(:role) |> admin_role?()

  def grants?(actor, permissions) when is_list(permissions) do
    Definitions.admin() not in permissions and
      (admin?(actor) or Enum.all?(permissions, &(&1 in actor.role.permissions)))
  end

  def grants?(_actor, _permissions), do: false

  def role?(actor, %Role{permissions: permissions} = role),
    do: not admin_role?(role) and grants?(actor, permissions)

  def branches?(actor, branch_ids) do
    admin?(actor) or MapSet.subset?(MapSet.new(branch_ids), MapSet.new(branch_ids(actor)))
  end

  def staff?(actor, %Staff{} = target) do
    target = Repo.preload(target, [:role, :branches])

    cond do
      admin_role?(target.role) ->
        target.id == actor.id

      admin?(actor) ->
        true

      true ->
        target.id != actor.id and role?(actor, target.role) and
          branches?(actor, branch_ids(target))
    end
  end

  def password?(actor, %Staff{} = target),
    do: target.id == actor.id or (Acl.can?(actor, "staff.update") and staff?(actor, target))

  def assignment?(actor, attrs, target \\ nil) do
    role_ok?(actor, value(attrs, :role_id), target) and
      branches_ok?(actor, value(attrs, :branch_ids))
  end

  defp role_ok?(_actor, id, _target) when id in [nil, ""], do: true
  defp role_ok?(_actor, id, %Staff{role_id: id}), do: true

  defp role_ok?(actor, id, %Staff{} = target) do
    not admin_staff?(target) and role_ok?(actor, id, nil)
  end

  defp role_ok?(actor, id, nil) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        case Repo.get(Role, uuid) do
          %Role{} = role -> role?(actor, role)
          nil -> true
        end

      :error ->
        true
    end
  end

  defp branches_ok?(_actor, nil), do: true
  defp branches_ok?(actor, ids), do: branches?(actor, Enum.reject(List.wrap(ids), &(&1 == "")))

  defp value(attrs, key), do: Map.get(attrs, Atom.to_string(key)) || Map.get(attrs, key)

  defp branch_ids(%Staff{} = staff),
    do: staff |> Repo.preload(:branches) |> Map.get(:branches) |> Enum.map(& &1.id)
end
