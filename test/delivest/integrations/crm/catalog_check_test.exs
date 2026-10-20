defmodule Delivest.Integrations.Crm.CatalogCheckTest do
  use ExUnit.Case, async: true

  alias Delivest.Integrations.Crm.CatalogCheck

  defp product(id, external_id, price),
    do: %{id: id, name: id, external_id: external_id, price: price}

  test "finds missing ids, missing products and price differences" do
    products = [
      product("same", "1", 100),
      product("pricey", "2", 200),
      product("gone", "3", 300),
      product("unlinked", nil, 400)
    ]

    catalog = [%{external_id: "1", price: 100}, %{external_id: "2", price: 250}]

    assert [
             %{
               "type" => "price_mismatch",
               "product_id" => "pricey",
               "app_price" => 200,
               "crm_price" => 250
             },
             %{"type" => "missing_in_crm", "product_id" => "gone"},
             %{"type" => "missing_crm_id", "product_id" => "unlinked"}
           ] = CatalogCheck.issues(products, catalog)
  end
end
