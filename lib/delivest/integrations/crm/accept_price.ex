defmodule Delivest.Integrations.Crm.AcceptPrice do
  @moduledoc "Accepts the server-displayed Frontpad price for a product owned by one branch."

  alias Delivest.Identity
  alias Delivest.Integrations.Crm.{BranchSettings, Catalog}
  alias Delivest.Net.{ProductCrmIds, Products, SharedOwnership}

  def run(staff, branch_id, product_id, crm_price)
      when is_integer(crm_price) and crm_price >= 0 and crm_price < 100_000_000 do
    with {:ok, _} <- valid_id(branch_id),
         {:ok, _} <- valid_id(product_id),
         :ok <- Identity.authorize(staff, "products.update", branch_id),
         :ok <- Identity.authorize(staff, "integrations.read", branch_id),
         :ok <- frontpad_provider(branch_id),
         :ok <- single_owner(product_id, branch_id),
         {:ok, external_id} <- crm_id(product_id, branch_id),
         {:ok, _} <-
           current_price(Catalog.get_snapshot(branch_id, :frontpad), external_id, crm_price) do
      case Products.accept_crm_price(staff, branch_id, product_id, external_id, crm_price) do
        {:ok, result} -> {:ok, result}
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

  defp frontpad_provider(branch_id) do
    case Delivest.Integrations.Crm.get_branch_settings(branch_id) do
      %BranchSettings{} = settings ->
        if BranchSettings.active_provider(settings) == :frontpad,
          do: :ok,
          else: {:error, :provider_changed}

      _ ->
        {:error, :provider_changed}
    end
  end

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

  defp current_price(%{products: catalog}, external_id, expected_price) do
    case Enum.find(catalog, &(Map.get(&1, "external_id", &1[:external_id]) == external_id)) do
      nil ->
        {:error, :missing_in_crm}

      row ->
        with {:ok, price} <- valid_price(Map.get(row, "price", row[:price])),
             :ok <- expected_price(price, expected_price),
             do: {:ok, price}
    end
  end

  defp current_price(_, _, _), do: {:error, :missing_in_crm}

  defp valid_price(price) when is_integer(price) and price >= 0 and price < 100_000_000,
    do: {:ok, price}

  defp valid_price(_price), do: {:error, :invalid_crm_price}

  defp expected_price(price, price), do: :ok
  defp expected_price(price, _expected), do: {:error, {:price_changed, price}}
end
