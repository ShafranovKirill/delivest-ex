defmodule Delivest.Identity.Roles do
  alias Delivest.Repo
  alias Delivest.Identity.{Role, Staff, Acl}
  import Ecto.Query

  @spec list_roles(map(), map()) ::
          {:ok, {[Role.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()} | {:error, :forbidden}
  def list_roles(user, params \\ %{}) do
    if Acl.can?(user, "roles.read") do
      Flop.validate_and_run(Role, params, for: Role)
    else
      {:error, :forbidden}
    end
  end

  @spec list_all_roles(map()) :: [Role.t()] | {:error, :forbidden}
  def list_all_roles(user) do
    if Acl.can?(user, "roles.read") do
      Repo.all(Role)
    else
      {:error, :forbidden}
    end
  end

  @spec get_role(map(), String.t()) ::
          {:ok, Role.t()} | {:error, :not_found} | {:error, :forbidden}
  def get_role(user, id) do
    if Acl.can?(user, "roles.read") do
      case Repo.get(Role, id) do
        nil -> {:error, :not_found}
        role -> {:ok, role}
      end
    else
      {:error, :forbidden}
    end
  end

  @spec get_role_by_name(String.t()) :: {:ok, Role.t()} | {:error, :not_found}
  def get_role_by_name(name) do
    case Repo.get_by(Role, name: name) do
      nil -> {:error, :not_found}
      role -> {:ok, role}
    end
  end

  @spec create_role(map(), map()) ::
          {:ok, Role.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def create_role(user, attrs) do
    if Acl.can?(user, "roles.create") do
      system_create_role(attrs)
    else
      {:error, :forbidden}
    end
  end

  @spec system_create_role(map()) :: {:ok, Role.t()} | {:error, Ecto.Changeset.t()}
  def system_create_role(attrs) do
    %Role{}
    |> Role.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_role(map(), Role.t(), map()) :: {:ok, Role.t()} | {:error, Ecto.Changeset.t()}
  def update_role(user, %Role{} = role, attrs) do
    if Acl.can?(user, "roles.update") do
      role
      |> Role.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, updated_role} ->
          clear_accounts_cache_for_role(updated_role.id)
          {:ok, updated_role}

        error ->
          error
      end
    else
      {:error, :forbidden}
    end
  end

  def delete_role(user, %Role{} = role) do
    if Acl.can?(user, "roles.delete") do
      role
      |> role_delete_changeset()
      |> Repo.delete()
      |> finalize_delete()
    else
      {:error, :forbidden}
    end
  end

  defp finalize_delete({:ok, role}), do: {:ok, role}

  defp finalize_delete({:error, %Ecto.Changeset{} = changeset}) do
    if has_foreign_key_error?(changeset) do
      {:error, :role_in_use}
    else
      {:error, changeset}
    end
  end

  defp has_foreign_key_error?(changeset) do
    Enum.any?(changeset.errors, fn {field, {_, meta}} ->
      field == :accounts and meta[:constraint] == :foreign
    end)
  end

  defp role_delete_changeset(role) do
    role
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.foreign_key_constraint(:accounts, name: :staff__role_id__fk)
  end

  defp clear_accounts_cache_for_role(role_id) do
    Staff
    |> where([s], s.role_id == ^role_id)
    |> select([s], s.id)
    |> Repo.all()
    |> Enum.each(&Cachex.del(:staff_cache, &1))
  end
end
