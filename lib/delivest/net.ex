defmodule Delivest.Net do
  alias Delivest.Net.{Categories, Catalogs, Products, Stocks}

  defdelegate list_category_for_branch(branch_id, opts \\ []), to: Categories
  defdelegate list_staff_categories_for_branch(staff, branch_id, opts \\ []), to: Categories
  defdelegate get_category(id, opts \\ []), to: Categories
  defdelegate create_category(staff, branch_id, attrs), to: Categories

  defdelegate update_category(staff, updateble_category, attrs), to: Categories
  defdelegate delete_category(staff, category), to: Categories
  defdelegate update_category_order(staff, category, above_order, below_order), to: Categories

  defdelegate list_staff_products_for_branch(staff, branch_id, params \\ %{}, opts \\ []),
    to: Products

  defdelegate create_product(staff, branch_id, attrs), to: Products
  defdelegate update_product(staff, product, attrs), to: Products
  defdelegate soft_delete_product(staff, product), to: Products
  defdelegate get_product(id, opts), to: Products
  defdelegate list_products_by_ids(ids, opts), to: Products

  defdelegate list_staff_stocks_for_branch(staff, branch_id), to: Stocks
  defdelegate list_stocks_for_branch(branch_id), to: Stocks
  defdelegate create_stock(staff, branch_id, attrs), to: Stocks
  defdelegate update_stock(staff, stock, attrs), to: Stocks
  defdelegate update_stock_order(staff, stock, above_order, below_order), to: Stocks
  defdelegate delete_stock(staff, stock), to: Stocks

  defdelegate get_menu_for_branch(branch_id), to: Catalogs
  defdelegate clear_menu_cache(branch_id), to: Catalogs
end
