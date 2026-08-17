defmodule Delivest.Identity do
  alias Delivest.Identity.{Staffs, Staff, Roles, Acl}

  defdelegate list_staff(staff, params \\ %{}, opts \\ []), to: Staffs
  defdelegate create_staff(staff, attrs), to: Staffs
  defdelegate update_staff(staff, updatable_staff, attrs), to: Staffs
  defdelegate change_password(staff, updatable_staff, attrs), to: Staffs
  defdelegate get_staff(id, opts \\ []), to: Staffs
  defdelegate get_staff_by_login(login), to: Staffs
  defdelegate soft_delete_staff(staff, removable_staff), to: Staffs
  defdelegate authenticate(login, password), to: Staffs
  defdelegate assign_branch_to_staff(admin, staff_id, branch_id), to: Staffs
  defdelegate revoke_branch_from_staff(staff_id, branch_id), to: Staffs
  defdelegate clear_cache(), to: Staffs

  defdelegate login_regex, to: Staff
  defdelegate password_regex, to: Staff

  defdelegate can?(staff, permission), to: Acl
  defdelegate can_any?(staff, permissions), to: Acl
  defdelegate scope_by_branch(query, staff, permission), to: Acl
  defdelegate has_branch_access?(staff, branch_id), to: Acl

  defdelegate list_all_roles(user), to: Roles
  defdelegate get_role(user, id), to: Roles
  defdelegate get_role_by_name(name), to: Roles
end
