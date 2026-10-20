defmodule Delivest.Integrations.Crm.CatalogCheck do
  def issues(products, crm_products) do
    crm_index = Map.new(crm_products, &{&1.external_id, &1})
    Enum.flat_map(products, &product_issues(&1, crm_index))
  end

  def key(issue), do: Map.take(issue, ["type", "product_id", "app_price", "crm_price"])

  defp product_issues(%{external_id: id} = product, _crm_index) when id in [nil, ""],
    do: [issue("missing_crm_id", product)]

  defp product_issues(product, crm_index) do
    case Map.get(crm_index, product.external_id) do
      nil -> [issue("missing_in_crm", product)]
      %{price: price} when price != product.price -> [issue("price_mismatch", product, price)]
      _same -> []
    end
  end

  defp issue(type, product, crm_price \\ nil) do
    %{
      "type" => type,
      "product_id" => product.id,
      "name" => product.name,
      "external_id" => product.external_id,
      "app_price" => product.price,
      "crm_price" => crm_price
    }
  end
end
