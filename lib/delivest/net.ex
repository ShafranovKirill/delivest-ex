defmodule Delivest.Net do
  alias Delivest.Net.Categories

  defdelegate list_category_for_branch(branch_id, opts \\ []), to: Categories
  defdelegate list_staff_categories_for_branch(staff, branch_id, opts \\ []), to: Categories
  defdelegate get_category(id, opts \\ []), to: Categories
  defdelegate create_category(staff, branch_id, attrs), to: Categories

  @spec update_category(Delivest.Identity.Staff.t(), Delivest.Net.Category.t(), map()) ::
          {:error, :forbidden | Ecto.Changeset.t()} | {:ok, Delivest.Net.Category.t()}
  defdelegate update_category(staff, updateble_category, attrs), to: Categories
  defdelegate delete_category(staff, category), to: Categories
  defdelegate update_category_order(staff, category, above_order, below_order), to: Categories
end
