defmodule Delivest.Identity do
  alias Delivest.Identity.{Staff, Staffs, Acl}

  defdelegate list_staff(staff, params \\ %{}, opts \\ []), to: Staffs
end
