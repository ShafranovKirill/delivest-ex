defmodule Delivest.Net do
  alias Delivest.Net.{Branches, BranchInfo}

  defdelegate list_branch(staff, opts \\ []), to: Branches
  defdelegate get_branch(id, opts \\ []), to: Branches
  defdelegate update_branch(staff, branch, branch_attrs, info_attrs), to: Branches
  defdelegate create_branch(staff, branch_attrs, info_attrs), to: Branches
  defdelegate soft_delete_branch(staff, branch), to: Branches

  defdelegate phone_regex(), to: BranchInfo
end
