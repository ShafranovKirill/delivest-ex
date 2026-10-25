defmodule Delivest.Net do
  alias Delivest.Net.{Catalogs, Categories, ProductCopier, Products, ProductTags, Stocks}

  defdelegate list_category_for_branch(branch_id, opts \\ []), to: Categories
  defdelegate list_staff_categories_for_branch(staff, branch_id, opts \\ []), to: Categories
  defdelegate list_branch_categories(branch_id), to: Categories
  defdelegate get_category(id, opts \\ []), to: Categories
  defdelegate create_category(staff, branch_id, attrs), to: Categories

  defdelegate update_category(staff, updateble_category, attrs), to: Categories
  defdelegate delete_category(staff, category), to: Categories
  defdelegate update_category_order(staff, category, above_order, below_order), to: Categories

  defdelegate list_staff_products_for_branch(staff, branch_id, params \\ %{}, opts \\ []),
    to: Products

  defdelegate create_product(staff, branch_id, attrs), to: Products
  defdelegate import_products(staff, branch_id, rows), to: Products
  defdelegate product_available_in_branch?(product_id, branch_id), to: Products
  defdelegate update_product(staff, product, attrs), to: Products
  defdelegate soft_delete_product(staff, product), to: Products
  defdelegate soft_delete_products(staff, branch_id, ids), to: Products
  defdelegate get_product(id, opts), to: Products
  defdelegate list_products_by_ids(ids, opts \\ []), to: Products
  defdelegate list_branch_products(branch_id), to: Products
  defdelegate list_category_products(branch_id, category_id), to: Products

  defdelegate update_product_order(staff, product, above_order, below_order),
    to: Products

  defdelegate copy_products(staff, selection, from_branch_id, to_branch_id),
    to: ProductCopier,
    as: :copy

  defdelegate get_branch_product_by_slug(branch_id, slug), to: Products
  defdelegate list_product_options_for_branch(branch_id), to: Products
  defdelegate list_branch_products_by_slugs(branch_id, slugs), to: Products

  defdelegate list_staff_stocks_for_branch(staff, branch_id), to: Stocks
  defdelegate list_stocks_for_branch(branch_id), to: Stocks
  defdelegate create_stock(staff, branch_id, attrs), to: Stocks
  defdelegate update_stock(staff, stock, attrs), to: Stocks
  defdelegate update_stock_order(staff, stock, above_order, below_order), to: Stocks
  defdelegate delete_stock(staff, stock), to: Stocks

  defdelegate list_product_tags, to: ProductTags, as: :list_tags
  defdelegate get_product_tag(id), to: ProductTags, as: :get_tag
  defdelegate change_product_tag(tag, attrs \\ %{}), to: ProductTags, as: :change_tag
  defdelegate create_product_tag(staff, attrs, upload \\ nil), to: ProductTags, as: :create_tag

  defdelegate update_product_tag(staff, tag, attrs, upload \\ nil),
    to: ProductTags,
    as: :update_tag

  defdelegate delete_product_tag(staff, tag), to: ProductTags, as: :delete_tag
  defdelegate product_tag_icon_url(tag), to: ProductTags, as: :icon_url

  defdelegate get_menu_for_branch(branch_id), to: Catalogs

  def get_branch_product(branch_id, id, opts \\ []),
    do: Delivest.Net.BranchScope.fetch(Delivest.Net.Product, branch_id, id, opts)

  def get_branch_category(branch_id, id, opts \\ []),
    do: Delivest.Net.BranchScope.fetch(Delivest.Net.Category, branch_id, id, opts)

  def get_branch_stock(branch_id, id, opts \\ []),
    do: Delivest.Net.BranchScope.fetch(Delivest.Net.Stock, branch_id, id, opts)

  defdelegate clear_menu_cache(branch_id), to: Catalogs
end
