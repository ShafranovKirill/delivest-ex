defmodule Delivest.Net.Categories do
  import Ecto.Query

  alias Delivest.{Repo, Identity}
  alias Delivest.Net.Category
  alias Delivest.Identity.Staff

  @spec list_category_for_branch(binary(), keyword()) :: [Category.t()]
  def list_category_for_branch(branch_id, opts \\ []) do
    Category
    |> where([c], c.branch_id == type(^branch_id, :binary_id))
    |> order_by([c], asc: c.order)
    |> maybe_preload_query(opts)
    |> Repo.all()
  end

  @spec list_staff_categories_for_branch(Staff.t(), binary(), keyword()) ::
          [Category.t()] | {:error, :forbidden}
  def list_staff_categories_for_branch(staff, branch_id, opts \\ []) do
    if Identity.can?(staff, "categories.read") do
      Category
      |> where([c], c.branch_id == type(^branch_id, :binary_id))
      |> order_by([c], asc: c.order)
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
      |> Repo.insert()
      |> case do
        {:ok, created_category} ->
          invalidate_menu_cache(created_category.branch_id)
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
      updateble_category
      |> Category.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, updated_category} ->
          invalidate_menu_cache(updateble_category.branch_id)

          {:ok, updated_category}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :forbidden}
    end
  end

  @spec delete_category(Staff.t(), Category.t()) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def delete_category(staff, %Category{} = category) do
    if Identity.can?(staff, "categories.delete") do
      case Repo.delete(category) do
        {:ok, deleted_category} ->
          invalidate_menu_cache(deleted_category.branch_id)
          {:ok, deleted_category}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :forbidden}
    end
  end

  defp invalidate_menu_cache(branch_id) when not is_nil(branch_id) do
    Cachex.del(:menu_cache, branch_id)
  end

  defp invalidate_menu_cache(_), do: :ok

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
