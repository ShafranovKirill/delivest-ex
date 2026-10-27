defmodule Delivest.Integrations.Frontpad.Api do
  alias Delivest.HTTP.Client

  @base_url "https://app.frontpad.ru"

  def new_order(form_params) do
    "/api/index.php?new_order"
    |> Client.post(form_params, base_url: @base_url, format: :form, decode_json: true)
    |> decode()
    |> result()
  end

  def get_products(secret) do
    "/api/index.php?get_products"
    |> Client.post([{"secret", secret}], base_url: @base_url, format: :form, decode_json: true)
    |> decode()
    |> products()
  end

  def get_stops(secret) do
    "/api/index.php?get_stops"
    |> Client.post([{"secret", secret}], base_url: @base_url, format: :form, decode_json: true)
    |> decode()
    |> stops()
  end

  defp stops({:ok, %{"result" => "success", "error" => "no_stops"}}), do: {:ok, []}

  defp stops({:ok, %{"result" => "success"} = body}),
    do: {:ok, body["product_id"] |> indexed() |> Enum.map(fn {_index, id} -> to_string(id) end)}

  defp stops(response), do: result(response)

  defp products({:ok, %{"result" => "success"} = body}) do
    names = Map.new(indexed(body["name"]))
    prices = Map.new(indexed(body["price"]))

    {:ok,
     body["product_id"]
     |> indexed()
     |> Enum.map(fn {index, external_id} ->
       %{
         external_id: to_string(external_id),
         name: names[index],
         price: parse_price(prices[index])
       }
     end)}
  end

  defp products({:ok, %{"result" => "error", "error" => "invalid_products"}}), do: {:ok, []}
  defp products(response), do: result(response)

  defp indexed(values) when is_list(values),
    do: values |> Enum.with_index(fn value, index -> {to_string(index), value} end)

  defp indexed(values) when is_map(values), do: Enum.to_list(values)
  defp indexed(_values), do: []

  defp parse_price(price) when is_number(price), do: round(price)

  defp parse_price(price) when is_binary(price) do
    case Float.parse(price) do
      {value, _rest} -> round(value)
      :error -> nil
    end
  end

  defp parse_price(_price), do: nil

  defp decode({:ok, body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, {:invalid_json, body, reason}}
    end
  end

  defp decode(response), do: response

  defp result({:ok, %{"result" => "success", "order_id" => order_id} = body}) do
    {:ok,
     %{
       external_id: to_string(order_id),
       external_number: body["order_number"] && to_string(body["order_number"]),
       warnings: body["warnings"]
     }}
  end

  defp result({:ok, %{"result" => "error", "error" => error}}), do: {:error, {:frontpad, error}}
  defp result({:ok, other}), do: {:error, {:unexpected_response, other}}
  defp result(error), do: error
end
