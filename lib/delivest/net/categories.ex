defmodule Delivest.Net.Categories do
  import Ecto.Query

  alias Ecto.Multi
  alias Delivest.{Repo, Identity, Relations}
  alias Delivest.Net.Category
  alias Delivest.Identity.Staff

  @spec list_category_for_branch(binary(), keyword()) :: [Category.t()]
  def list_category_for_branch(branch_id, opts \\ []) do
    category_ids = Relations.list_target_ids("Branch", branch_id, "Category")

    Category
    |> where([c], c.id in ^category_ids)
    |> where([c], c.is_active == true)
    |> order_by([c], asc: c.order)
    |> maybe_preload_query(opts)
    |> Repo.all()
  end

  @spec list_staff_categories_for_branch(Staff.t(), binary(), keyword()) ::
          [Category.t()] | {:error, :forbidden}
  def list_staff_categories_for_branch(staff, branch_id, opts \\ []) do
    if Identity.can?(staff, "categories.read") do
      category_ids = Relations.list_target_ids("Branch", branch_id, "Category")

      Category
      |> where([c], c.id in ^category_ids)
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

  @spec create_category(Staff.t(), binary(), map()) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def create_category(staff, branch_id, attrs) do
    if Identity.can?(staff, "categories.create") do
      next_order = calculate_next_order(branch_id)

      attrs_with_order =
        attrs
        |> Map.put("order", next_order)

      Multi.new()
      |> Multi.insert(:category, Category.changeset(%Category{}, attrs_with_order))
      |> Multi.run(:relation, fn _repo, %{category: category} ->
        case Relations.create_relation("Branch", branch_id, "Category", category.id) do
          {:ok, relation} -> {:ok, relation}
          {:error, reason} -> {:error, reason}
        end
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{category: created_category}} ->
          invalidate_menu_cache(branch_id)
          {:ok, created_category}

        {:error, _failed_operation, error, _changes_so_far} ->
          {:error, error}
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
          branch_id = get_category_branch_id(updated_category.id)
          invalidate_menu_cache(branch_id)
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
          branch_id = get_category_branch_id(deleted_category.id)

          invalidate_menu_cache(branch_id)
          {:ok, deleted_category}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :forbidden}
    end
  end

  @spec update_category_order(Staff.t(), Category.t(), float() | nil, float() | nil) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def update_category_order(staff, %Category{} = category, above_order, below_order) do
    if Identity.can?(staff, "categories.update") do
      new_order = calculate_new_order(above_order, below_order)

      category
      |> Category.changeset(%{"order" => new_order})
      |> Repo.update()
      |> case do
        {:ok, updated_category} ->
          branch_id = get_category_branch_id(updated_category.id)
          invalidate_menu_cache(branch_id)

          {:ok, updated_category}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :forbidden}
    end
  end

  defp get_category_branch_id(category_id) do
    Relations.list_source_ids("Category", category_id, "Branch")
    |> List.first()
  end

  defp calculate_new_order(above_order, below_order)
       when not is_nil(above_order) and not is_nil(below_order) do
    (above_order + below_order) / 2.0
  end

  defp calculate_new_order(nil, below_order) when not is_nil(below_order) do
    if below_order > 0.0 do
      below_order / 2.0
    else
      below_order - 1.0
    end
  end

  defp calculate_new_order(above_order, nil) when not is_nil(above_order) do
    above_order + 1.0
  end

  defp calculate_new_order(nil, nil) do
    1.0
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

  defp calculate_next_order(branch_id) when not is_nil(branch_id) do
    category_ids = Relations.list_target_ids("Branch", branch_id, "Category")

    max_order =
      Category
      |> where([c], c.id in ^category_ids)
      |> select([c], max(c.order))
      |> Repo.one()

    case max_order do
      nil -> 1.0
      val -> val + 1.0
    end
  end

  defp calculate_next_order(_), do: 1.0
end
