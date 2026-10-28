defmodule Delivest.YandexEdaContract.Collection do
  @source Path.join(__DIR__, "rest_for_partners.postman_collection.json")
  @external_resource @source

  @sequence [
    {"POST", "/security/oauth/token"},
    {"GET", "/restaurants"},
    {"GET", "/composition"},
    {"GET", "/availability"},
    {"POST", "/order"},
    {"GET", "/order/{{order_id}}"},
    {"PUT", "/order/{{order_id}}"},
    {"GET", "/order/{{order_id}}/status"},
    {"DELETE", "/order/{{order_id}}"}
  ]

  @bearer %{
    "type" => "bearer",
    "bearer" => [%{"key" => "token", "value" => "{{access_token}}", "type" => "string"}]
  }

  def prepare(%{host: host, settings: settings, branch: branch, product: product}) do
    eats_id = "contract-#{System.unique_integer([:positive])}"
    collection = @source |> File.read!() |> Jason.decode!()

    requests =
      collection["item"]
      |> flatten()
      |> Enum.flat_map(&placed/1)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {_rank, item} -> item |> authorize() |> fix_scripts() end)
      |> Enum.map(&with_order(&1, eats_id, product))

    collection
    |> Map.delete("auth")
    |> Map.put("item", requests)
    |> Map.put("variable", [
      variable("host", host),
      variable("client_id", settings.client_id),
      variable("client_secret", settings.client_secret),
      variable("restaurant_id", branch.id)
    ])
  end

  defp flatten(items),
    do: Enum.flat_map(items, &if(Map.has_key?(&1, "item"), do: flatten(&1["item"]), else: [&1]))

  defp placed(%{"request" => request} = item) do
    url = request["url"]["raw"]

    case Enum.find_index(@sequence, fn {method, suffix} ->
           request["method"] == method and String.ends_with?(url, suffix)
         end) do
      nil -> []
      rank -> [{rank, item}]
    end
  end

  defp authorize(%{"request" => %{"auth" => %{"type" => "noauth"}}} = item), do: item
  defp authorize(item), do: put_in(item, ["request", "auth"], @bearer)

  defp fix_scripts(item) do
    events =
      Enum.map(item["event"] || [], fn event ->
        update_in(event, ["script", "exec"], fn lines ->
          lines
          |> Enum.reject(&(String.trim(&1) == "A"))
          |> Enum.map(&String.replace(&1, ~r/;\s*a$/, ";"))
          |> Enum.map(
            &String.replace(
              &1,
              "item.images[0].url.includes(",
              "item.images?.[0]?.url?.includes("
            )
          )
          |> Enum.map(&String.replace(&1, "item.images[0].url ==", "item.images?.[0]?.url =="))
        end)
      end)

    Map.put(item, "event", events)
  end

  defp with_order(%{"request" => %{"method" => method}} = item, eats_id, product)
       when method in ["POST", "PUT"] do
    case item["request"]["body"] do
      %{"mode" => "raw", "raw" => raw} ->
        body =
          raw
          |> Jason.decode!()
          |> Map.merge(%{
            "eatsId" => eats_id,
            "restaurantId" => "{{restaurant_id}}",
            "items" => [order_item(product)],
            "paymentInfo" => %{"itemsCost" => product.price, "paymentType" => "CARD"}
          })

        put_in(item, ["request", "body", "raw"], Jason.encode!(body))

      _other ->
        item
    end
  end

  defp with_order(item, _eats_id, _product), do: item

  defp order_item(product),
    do: %{
      "id" => product.id,
      "name" => product.name,
      "quantity" => 1,
      "price" => product.price,
      "modifications" => [],
      "promos" => []
    }

  defp variable(key, value), do: %{"key" => key, "value" => value, "type" => "string"}
end
