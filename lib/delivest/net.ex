defmodule Delivest.Net do
  alias Delivest.Net.Categories
  alias Delivest.Net.{Branches, BranchInfo}

  defdelegate list_branch_for_staff(staff, opts \\ []), to: Branches
  defdelegate list_all_branch(opts), to: Branches
  defdelegate get_branch(id, opts \\ []), to: Branches
  defdelegate update_branch(staff, branch, branch_attrs, info_attrs), to: Branches
  defdelegate create_branch(staff, branch_attrs, info_attrs), to: Branches
  defdelegate soft_delete_branch(staff, branch), to: Branches

  defdelegate list_category_for_branch(branch_id, opts \\ []), to: Categories
  defdelegate list_staff_categories_for_branch(staff, branch_id, opts \\ []), to: Categories
  defdelegate get_category(id, opts \\ []), to: Categories
  defdelegate create_category(staff, branch_id, attrs), to: Categories
  defdelegate update_category(staff, updateble_category, attrs), to: Categories
  defdelegate delete_category(staff, category), to: Categories
  defdelegate update_category_order(staff, category, above_order, below_order), to: Categories

  defdelegate phone_regex(), to: BranchInfo
end
