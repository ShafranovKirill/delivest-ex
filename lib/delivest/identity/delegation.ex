defmodule Delivest.Identity.Delegation do
  alias Delivest.Identity.{Acl, Role, Staff}
  alias Delivest.Repo

  def admin?(actor), do: Acl.can?(actor, "admin")

  def grants?(actor, permissions) when is_list(permissions) do
    admin?(actor) or
      ("admin" not in permissions and Enum.all?(permissions, &(&1 in actor.role.permissions)))
  end

  def grants?(_actor, _permissions), do: false

  def role?(actor, %Role{permissions: permissions}), do: grants?(actor, permissions)

  def branches?(actor, branch_ids) do
    admin?(actor) or MapSet.subset?(MapSet.new(branch_ids), MapSet.new(branch_ids(actor)))
  end

  def staff?(actor, %Staff{} = target) do
    target = Repo.preload(target, [:role, :branches])

    admin?(actor) or
      (target.id != actor.id and role?(actor, target.role) and
         branches?(actor, branch_ids(target)))
  end

  def assignment?(actor, attrs) do
    role_ok?(actor, value(attrs, :role_id)) and branches_ok?(actor, value(attrs, :branch_ids))
  end

  defp role_ok?(_actor, id) when id in [nil, ""], do: true

  defp role_ok?(actor, id) do
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
