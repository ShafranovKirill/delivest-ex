defmodule Delivest.Integrations.Frontpad.Api do
  alias Delivest.HTTP.Client
  alias Delivest.Money

  @base_url "https://app.frontpad.ru"

  def new_order(form_params) do
    "/api/index.php?new_order"
    |> Client.post(form_params, base_url: @base_url, format: :form, journal: :frontpad)
    |> decode()
    |> result()
  end

  def get_products(secret) do
    "/api/index.php?get_products"
    |> Client.post([{"secret", secret}], base_url: @base_url, format: :form, journal: :frontpad)
    |> decode()
    |> products()
  end

  def get_certificate(secret, certificate) do
    "/api/index.php?get_certificate"
    |> Client.post([{"secret", secret}, {"certificate", certificate}],
      base_url: @base_url,
      format: :form,
      journal: :frontpad
    )
    |> decode()
    |> certificate()
  end

  defp certificate(
         {:ok, %{"result" => "success", "product_id" => id, "name" => name, "price" => price}}
       )
       when (is_binary(id) or is_integer(id)) and is_binary(name) do
    case certificate_price(price) do
      {:ok, value} when byte_size(name) > 0 ->
        {:ok, %{type: :product, product_id: to_string(id), name: name, price: value}}

      _ ->
        {:error, :invalid_certificate_response}
    end
  end

  defp certificate({:ok, %{"result" => "success", "sale" => sale}})
       when is_binary(sale) or is_integer(sale),
       do: certificate_sale(to_string(sale))

  defp certificate({:ok, %{"result" => "success", "amount" => amount}}) do
    case certificate_price(amount) do
      {:ok, value} -> {:ok, %{type: :amount, amount: value}}
      :error -> {:error, :invalid_certificate_response}
    end
  end

  defp certificate({:ok, %{"result" => "error", "error" => error}}),
    do: {:error, {:frontpad, error}}

  defp certificate({:ok, _body}), do: {:error, :invalid_certificate_response}
  defp certificate(error), do: error

  defp certificate_sale(value) do
    case Integer.parse(value) do
      {sale, ""} when sale in 1..100 -> {:ok, %{type: :percent, sale: sale}}
      _ -> {:error, :invalid_certificate_response}
    end
  end

  defp certificate_price(value) when is_binary(value) do
    case Money.parse(value) do
      {:ok, amount} when amount >= 0 -> {:ok, amount}
      _ -> :error
    end
  end

  defp certificate_price(value) when is_integer(value) and value >= 0,
    do: {:ok, Money.from_rubles(value)}

  defp certificate_price(_value), do: :error

  def get_stops(secret) do
    "/api/index.php?get_stops"
    |> Client.post([{"secret", secret}], base_url: @base_url, format: :form, journal: :frontpad)
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

  defp parse_price(price) when is_number(price), do: Money.from_rubles(price)

  defp parse_price(price) when is_binary(price) do
    case Float.parse(price) do
      {value, _rest} -> Money.from_rubles(value)
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
