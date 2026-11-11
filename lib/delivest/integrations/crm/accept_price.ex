defmodule Delivest.Integrations.Crm.AcceptPrice do
  @moduledoc "Accepts a fresh Frontpad price for a product owned by one branch."

  alias Delivest.Identity
  alias Delivest.Integrations.Crm.Catalog
  alias Delivest.Net.{ProductCrmIds, Products, SharedOwnership}

  def run(staff, branch_id, product_id, expected_crm_price)
      when is_integer(expected_crm_price) and expected_crm_price >= 0 do
    with {:ok, _} <- valid_id(branch_id),
         {:ok, _} <- valid_id(product_id),
         :ok <- Identity.authorize(staff, "products.update", branch_id),
         :ok <- Identity.authorize(staff, "integrations.read", branch_id),
         :ok <- single_owner(product_id, branch_id),
         {:ok, external_id} <- crm_id(product_id, branch_id),
         {:ok, catalog} <- Catalog.fetch_current(branch_id, :frontpad),
         {:ok, fresh_price} <- current_price(catalog, external_id),
         :ok <- expected_price(fresh_price, expected_crm_price) do
      case Products.accept_crm_price(staff, branch_id, product_id, external_id, fresh_price) do
        {:ok, result} -> {:ok, result, catalog}
        error -> error
      end
    else
      :error -> {:error, :invalid_id}
      error -> error
    end
  end

  def run(_staff, _branch_id, _product_id, _expected_price), do: {:error, :invalid_price}

  defp valid_id(id) when is_binary(id), do: Ecto.UUID.cast(id)
  defp valid_id(_id), do: :error

  defp single_owner(product_id, branch_id) do
    case SharedOwnership.branches("Product", product_id) do
      [^branch_id] -> :ok
      [] -> {:error, :product_not_found}
      owners -> if(branch_id in owners, do: {:error, :shared_product}, else: {:error, :forbidden})
    end
  end

  defp crm_id(product_id, branch_id) do
    case ProductCrmIds.by_product([product_id], :frontpad, branch_id)[product_id] do
      nil -> {:error, :mapping_missing}
      id -> {:ok, id}
    end
  end

  defp current_price(catalog, external_id) do
    case Enum.find(catalog, &(Map.get(&1, :external_id, &1["external_id"]) == external_id)) do
      nil -> {:error, :missing_in_crm}
      row -> valid_price(Map.get(row, :price, row["price"]))
    end
  end

  defp valid_price(price) when is_integer(price) and price >= 0 and price < 100_000_000,
    do: {:ok, price}

  defp valid_price(_price), do: {:error, :invalid_crm_price}

  defp expected_price(price, price), do: :ok
  defp expected_price(price, _expected), do: {:error, {:price_changed, price}}
end
