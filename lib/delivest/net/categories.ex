defmodule Delivest.Net.Categories do
  import Ecto.Query

  alias Delivest.{Repo, Identity}
  alias Delivest.Net.{Category, Branch}
  alias Delivest.Identity.Staff

  @spec list_category_for_branch(binary(), keyword()) :: [Category.t()]
  def list_category_for_branch(branch_id, opts \\ []) do
    Category
    |> join(:inner, [c], cb in "categories_branches", on: cb.category_id == c.id)
    |> where([c, cb], cb.branch_id == type(^branch_id, :binary_id) and c.is_active == true)
    |> order_by([_c, cb], asc: cb.order)
    |> maybe_preload_query(opts)
    |> Repo.all()
  end

  @spec list_staff_categories_for_branch(Staff.t(), binary(), keyword()) ::
          [Category.t()] | {:error, :forbidden}
  def list_staff_categories_for_branch(staff, branch_id, opts \\ []) do
    if Identity.can?(staff, "categories.read") do
      Category
      |> join(:inner, [c], cb in "categories_branches", on: cb.category_id == c.id)
      |> where([c, cb], cb.branch_id == type(^branch_id, :binary_id))
      |> order_by([_c, cb], asc: cb.order)
      |> maybe_preload_query(opts)
      |> Repo.all()
    else
      {:error, :forbidden}
    end
  end

  @spec get_category(binary(), keyword()) :: {:ok, Category.t()} | {:error, :not_found}
  def get_category(id, opts \\ []) do
    case Repo.get(Category, id) do
      nil ->
        {:error, :not_found}

      category ->
        category = maybe_preload_category(category, opts)
        {:ok, category}
    end
  end

  @spec create_category(Staff.t(), map()) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def create_category(staff, attrs) do
    if Identity.can?(staff, "categories.create") do
      %Category{}
      |> Category.changeset(attrs)
      |> put_branches(attrs)
      |> Repo.insert()
      |> case do
        {:ok, created_category} ->
          created_category = Repo.preload(created_category, :branches)

          invalidate_menu_cache(created_category.branches)

          {:ok, created_category}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :forbidden}
    end
  end

  @spec update_category(Staff.t(), Category.t(), map()) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def update_category(staff, %Category{} = updateble_category, attrs) do
    if Identity.can?(staff, "categories.update") do
      old_category = maybe_preload_category(updateble_category, preload: [:branches])

      old_category
      |> Category.changeset(attrs)
      |> put_branches(attrs)
      |> Repo.update()
      |> case do
        {:ok, updated_category} ->
          updated_category = Repo.preload(updated_category, :branches, force: true)

          invalidate_menu_cache(old_category.branches ++ updated_category.branches)

          {:ok, updated_category}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :forbidden}
    end
  end

  def delete_category(staff, %Category{} = category) do
    if Identity.can?(staff, "categories.delete") do
      category_with_branches = Repo.preload(category, :branches)

      case Repo.delete(category) do
        {:ok, deleted_category} ->
          invalidate_menu_cache(category_with_branches.branches)
          {:ok, deleted_category}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :forbidden}
    end
  end

  defp invalidate_menu_cache(branches) do
    branches
    |> Enum.map(& &1.id)
    |> Enum.uniq()
    |> Enum.each(fn branch_id ->
      Cachex.del(:menu_cache, branch_id)
    end)
  end

  defp put_branches(changeset, attrs) do
    branch_ids = attrs["branch_ids"] || attrs[:branch_ids]

    case branch_ids do
      nil ->
        changeset

      branch_ids ->
        branches = Repo.all(from b in Branch, where: b.id in ^branch_ids)
        Ecto.Changeset.put_assoc(changeset, :branches, branches)
    end
  end

  defp maybe_preload_category(category, opts) do
    case Keyword.get(opts, :preload) do
      nil -> category
      preloads -> Repo.preload(category, preloads)
    end
  end

  defp maybe_preload_query(query, opts) do
    case Keyword.get(opts, :preload) do
      nil -> query
      preloads -> preload(query, ^preloads)
    end
  end
end
