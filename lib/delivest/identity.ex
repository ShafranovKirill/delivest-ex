defmodule Delivest.Identity do
  alias Delivest.Identity.{Staffs}

  defdelegate list_staff(staff, params \\ %{}, opts \\ []), to: Staffs
end
