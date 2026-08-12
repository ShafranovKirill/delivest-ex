defmodule Delivest.Identity do
  alias Delivest.Identity.{Staffs, Staff, Roles}

  defdelegate list_staff(staff, params \\ %{}, opts \\ []), to: Staffs
  defdelegate create_staff(staff, attrs), to: Staffs
  defdelegate update_staff(staff, updatable_staff, attrs), to: Staffs
  defdelegate change_password(staff, updatable_staff, attrs), to: Staffs
  defdelegate get_staff(id, opts \\ []), to: Staffs
  defdelegate soft_delete_staff(staff, removable_staff), to: Staffs
  defdelegate authenticate(login, password), to: Staffs

  defdelegate login_regex, to: Staff
  defdelegate password_regex, to: Staff

  defdelegate list_all_roles(user), to: Roles
  defdelegate get_role(user, id), to: Roles
  defdelegate get_role_by_name(name), to: Roles
end
