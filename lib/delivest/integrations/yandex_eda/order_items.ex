defmodule Delivest.Integrations.YandexEda.OrderItems do
  alias Delivest.Money

  def parse([_ | _] = items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case item(item) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        error -> {:halt, error}
      end
    end)
    |> merge()
  end

  def parse(_items), do: {:error, "items are required"}

  defp item(%{"id" => id, "quantity" => quantity, "price" => price} = item)
       when is_binary(id) and is_number(quantity) and quantity > 0 and is_number(price) and
              price >= 0,
       do: modified(id, item, ceil(quantity), Money.from_rubles(price))

  defp item(_item), do: {:error, "every item needs id, quantity and price"}

  defp modified(id, item, quantity, price) do
    modifiers = item |> Map.get("modifications", []) |> List.wrap() |> Enum.map(&modifier/1)
    unit = price + (modifiers |> Enum.map(&(&1.price * &1.quantity)) |> Enum.sum())

    {:ok,
     %{
       product_id: id,
       name: item["name"] || id,
       quantity: quantity,
       total: unit * quantity,
       modifiers: modifiers
     }}
  end

  defp modifier(modification) do
    %{
      id: modification["id"],
      group_name: nil,
      name: modification["name"] || modification["id"] || "",
      price: Money.from_rubles(modification["price"] || 0),
      quantity: modification["quantity"] || 1
    }
  end

  def key(%{product_id: id, modifiers: []}), do: id

  def key(%{product_id: id, modifiers: modifiers}),
    do: id <> "~" <> Delivest.Net.Modifiers.key(modifiers)

  defp merge({:ok, items}) do
    {:ok,
     items
     |> Enum.reverse()
     |> Enum.group_by(&key/1)
     |> Enum.map(fn {_id, [first | _] = same} ->
       %{
         first
         | quantity: same |> Enum.map(& &1.quantity) |> Enum.sum(),
           total: same |> Enum.map(& &1.total) |> Enum.sum()
       }
     end)}
  end

  defp merge(error), do: error
end
