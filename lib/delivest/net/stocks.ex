defmodule Delivest.Net.Stocks do
  import Ecto.Query

  alias Delivest.Net.Stock
  alias Ecto.Multi
  alias Delivest.{Repo, Identity, Relations}

  def list_staff_stocks_for_branch(staff, branch_id) when not is_nil(branch_id) do
    if Identity.can?(staff, "stocks.read") do
      stock_ids = Relations.list_target_ids("Branch", branch_id, "Stock")

      if stock_ids != [] do
        Stock
        |> where([s], s.id in ^stock_ids)
        |> preload(:media)
        |> Repo.all()
      else
        []
      end
    else
      {:error, :forbidden}
    end
  end

  def list_staff_stocks_for_branch(_staff, _branch_id), do: []

  def list_stocks_for_branch(branch_id) when not is_nil(branch_id) do
    case Cachex.get(:stock_cache, branch_id) do
      {:ok, stocks} when is_list(stocks) ->
        stocks

      _ ->
        stocks = fetch_stocks_for_branch(branch_id)
        Cachex.put(:stock_cache, branch_id, stocks, ttl: :timer.hours(1))
        stocks
    end
  end

  def list_stocks_for_branch(_), do: []

  def create_stock(staff, branch_id, attrs) do
    if Identity.can?(staff, "stocks.create") do
      Multi.new()
      |> Multi.insert(:stock, Stock.changeset(%Stock{}, attrs))
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
          invalidate_stock_cache(branch_id)
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
          invalidate_stock_cache(branch_id)
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
          invalidate_stock_cache(branch_id)
          {:ok, deleted_stock}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :forbidden}
    end
  end

  defp fetch_stocks_for_branch(branch_id) do
    stock_ids = Relations.list_target_ids("Branch", branch_id, "Stock")

    if stock_ids != [] do
      Stock
      |> where([s], s.id in ^stock_ids and s.is_active == true)
      |> preload(:media)
      |> Repo.all()
    else
      []
    end
  end

  defp get_stock_branch_id(stock_id) do
    Relations.list_source_ids("Stock", stock_id, "Branch")
    |> List.first()
  end

  defp invalidate_stock_cache(branch_id) when not is_nil(branch_id) do
    Cachex.del(:stock_cache, branch_id)
  end

  defp invalidate_stock_cache(_), do: :ok
end
