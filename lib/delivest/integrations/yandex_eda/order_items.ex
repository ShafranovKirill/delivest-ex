defmodule Delivest.Integrations.YandexEda.OrderItems do
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
       do:
         {:ok,
          %{
            product_id: id,
            name: item["name"] || id,
            quantity: ceil(quantity),
            total: floor(price) * ceil(quantity)
          }}

  defp item(_item), do: {:error, "every item needs id, quantity and price"}

  defp merge({:ok, items}) do
    {:ok,
     items
     |> Enum.reverse()
     |> Enum.group_by(& &1.product_id)
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
