defmodule Delivest.Integrations.Iiko.Menu do
  @product_types ~w(Dish Good)

  def parse(body) do
    products = Map.get(body, "products", []) |> Enum.reject(&Map.get(&1, "isDeleted", false))
    by_id = Map.new(products, &{&1["id"], &1})
    sizes = Map.new(Map.get(body, "sizes", []), &{&1["id"], &1["name"]})

    %{
      categories:
        body
        |> Map.get("groups", [])
        |> Enum.reject(
          &(Map.get(&1, "isDeleted", false) or Map.get(&1, "isGroupModifier", false))
        )
        |> Enum.map(&%{external_id: &1["id"], name: &1["name"]}),
      products:
        products
        |> Enum.filter(&(&1["type"] in @product_types))
        |> Enum.map(&product(&1, by_id, sizes))
    }
  end

  defp product(product, by_id, sizes) do
    prices = size_prices(product)
    base = prices |> Enum.map(&elem(&1, 1)) |> Enum.min(fn -> 0 end)

    %{
      external_id: product["id"],
      name: product["name"],
      category: product["parentGroup"],
      price: base,
      weight: weight(product["weight"]),
      groups: size_group(product, prices, base, sizes) ++ modifier_groups(product, by_id)
    }
  end

  defp size_prices(product) do
    product
    |> Map.get("sizePrices", [])
    |> Enum.flat_map(fn
      %{"price" => %{"currentPrice" => price} = info} = size when is_number(price) ->
        if Map.get(info, "isIncludedInMenu", true),
          do: [{size["sizeId"], round(price * 100)}],
          else: []

      _other ->
        []
    end)
  end

  defp size_group(_product, prices, _base, _sizes) when length(prices) < 2, do: []

  defp size_group(product, prices, base, sizes) do
    [
      %{
        external_id: "#{product["id"]}:sizes",
        name: "Размер",
        min: 1,
        max: 1,
        size: true,
        modifiers:
          Enum.map(prices, fn {size_id, price} ->
            %{
              external_id: "#{product["id"]}:#{size_id}",
              name: Map.get(sizes, size_id) || "—",
              price: price - base,
              default: price == base
            }
          end)
      }
    ]
  end

  defp modifier_groups(product, by_id) do
    product
    |> Map.get("groupModifiers", [])
    |> Enum.map(fn group ->
      %{
        external_id: group["id"],
        name: get_in(by_id, [group["id"], "name"]) || "Модификаторы",
        min: group["minAmount"] || 0,
        max: group["maxAmount"] || 1,
        size: false,
        modifiers:
          group
          |> Map.get("childModifiers", [])
          |> Enum.map(&Map.get(by_id, &1["id"]))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(fn modifier ->
            %{
              external_id: modifier["id"],
              name: modifier["name"],
              price: modifier |> size_prices() |> Enum.map(&elem(&1, 1)) |> Enum.min(fn -> 0 end)
            }
          end)
      }
    end)
  end

  defp weight(kg) when is_number(kg) and kg > 0, do: round(kg * 1000)
  defp weight(_kg), do: nil
end
