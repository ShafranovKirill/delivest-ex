defmodule Delivest.Integrations.Frontpad.Warnings do
  use Gettext, backend: DelivestWeb.Gettext

  @critical ~w(invalid_product_keys invalid_hook_status invalid_datetime)

  def apply(%{warnings: warnings} = delivery, payload, order) when is_map(warnings) do
    case alerts(warnings, payload, order) do
      [] -> delivery
      alerts -> Map.put(delivery, :alert, Enum.join(alerts, ". "))
    end
  end

  def apply(delivery, _payload, _order), do: delivery

  defp alerts(warnings, payload, order) do
    warnings
    |> Map.take(@critical)
    |> Enum.map(fn {kind, value} -> text(kind, value, payload, order) end)
  end

  defp text("invalid_product_keys", value, payload, _order) do
    articles =
      value
      |> indexes()
      |> Enum.map(&Enum.at(payload.products, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map_join(", ", &"#{&1.external_id} ×#{&1.quantity}")

    gettext("Frontpad did not accept the items: %{articles}. Check the articles",
      articles: articles
    )
  end

  defp text("invalid_hook_status", _value, _payload, _order),
    do:
      gettext("Frontpad did not accept the webhook statuses, the order statuses will not arrive")

  defp text("invalid_datetime", _value, _payload, order),
    do:
      gettext(
        "Frontpad did not accept the time of the preorder, order %{number} is cooked at once",
        number: order.number
      )

  defp indexes(value) when is_list(value), do: Enum.flat_map(value, &index/1)
  defp indexes(value) when is_map(value), do: value |> Map.keys() |> Enum.flat_map(&index/1)
  defp indexes(value), do: index(value)

  defp index(value) when is_integer(value), do: [value]

  defp index(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> [int]
      _ -> []
    end
  end

  defp index(_value), do: []
end
