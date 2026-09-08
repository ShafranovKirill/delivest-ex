defmodule Delivest.Net.Stocks do
  alias Delivest.Net.Stock
  alias Ecto.Multi
  alias Delivest.{Repo, Identity, Relations}

  def get_staff_stock_for_branch(staff, branch_id) do
    if Identity.can?(staff, "stocks.read") do
      stock_id =
        Relations.list_target_ids("Branch", branch_id, "Stock")
        |> List.first()

      if stock_id do
        Repo.get(Stock, stock_id)
      else
        nil
      end
    else
      {:error, :forbidden}
    end
  end

  def create_stock(staff, branch_id, attrs) do
    if Identity.can?(staff, "stocks.create") do
      Multi.new()
      |> Multi.insert(:stock, Stock.changeset(%Stock{}, attrs))
      |> Multi.run(:clear_old_relations, fn _repo, %{stock: stock} ->
        old_stock_ids = Relations.list_target_ids("Branch", branch_id, "Stock")

        Enum.each(old_stock_ids, fn old_id ->
          Relations.delete_relation("Branch", branch_id, "Stock", old_id)
        end)

        {:ok, stock}
      end)
      |> Multi.run(:relation_branch, fn repo, %{stock: stock} ->
        case Relations.create_relation(
               repo,
               "Branch",
               branch_id,
               "Stock",
               stock.id,
               %{}
             ) do
          {:ok, relation} -> {:ok, relation}
          {:error, reason} -> {:error, reason}
        end
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{stock: created_stock}} ->
          invalidate_branch_cache(branch_id)
          {:ok, created_stock}

        {:error, _failed_operation, error, _changes_so_far} ->
          {:error, error}
      end
    else
      {:error, :forbidden}
    end
  end

  def update_stock(staff, %Stock{} = updatable_stock, attrs) do
    if Identity.can?(staff, "stocks.update") do
      updatable_stock
      |> Stock.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, updated_stock} ->
          branch_id = get_stock_branch_id(updated_stock.id)
          invalidate_branch_cache(branch_id)
          {:ok, updated_stock}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :forbidden}
    end
  end

  def delete_stock(staff, %Stock{} = stock) do
    if Identity.can?(staff, "stocks.delete") do
      branch_id = get_stock_branch_id(stock.id)

      case Repo.delete(stock) do
        {:ok, deleted_stock} ->
          invalidate_branch_cache(branch_id)
          {:ok, deleted_stock}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :forbidden}
    end
  end

  defp get_stock_branch_id(stock_id) do
    Relations.list_source_ids("Stock", stock_id, "Branch")
    |> List.first()
  end

  defp invalidate_branch_cache(branch_id) when not is_nil(branch_id) do
    Cachex.del(:branch_cache, branch_id)
  end

  defp invalidate_branch_cache(_), do: :ok
end
