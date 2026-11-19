defmodule Delivest.Promo.CertificateComparison do
  @moduledoc "Compares the benefit described by Frontpad with website promotion rules."

  alias Delivest.Net
  alias Delivest.Net.ProductCrmIds
  alias Delivest.Promo.Dsl

  def warnings(snapshot, rules, branch_id) when is_map(snapshot) and is_binary(rules) do
    case Dsl.parse(rules) do
      {:ok, strategy} ->
        benefit =
          case {snapshot, strategy.effects} do
            {%{"type" => "percent", "sale" => sale}, [{:percent, sale, :cart, nil}]} ->
              []

            {%{"type" => "amount", "amount" => amount}, [{:amount, amount, :cart}]} ->
              []

            {%{"type" => "product"} = product, effects} ->
              if product_matches?(product, effects, branch_id),
                do: [],
                else: [
                  "Товар или цена сертификата отличается от правил сайта. Для клиента действуют правила сайта."
                ]

            _ ->
              [
                "Выгода сертификата отличается от простой скидки в правилах сайта. Для клиента действуют правила сайта."
              ]
          end

        conditions =
          if strategy.condition,
            do: [
              "Frontpad API не возвращает условия, срок и лимиты сертификата. Проверьте их во Frontpad вручную."
            ],
            else: [
              "Frontpad API не возвращает срок и лимиты сертификата. Проверьте их во Frontpad вручную."
            ]

        export =
          if snapshot["type"] == "percent",
            do: [
              "Процентная скидка передаётся в CRM по расчёту сайта; сертификат Frontpad автоматически не активируется."
            ],
            else: []

        benefit ++ conditions ++ export

      {:error, _} ->
        ["Не удалось сравнить выгоду: проверьте правила промокода на сайте."]
    end
  end

  def warnings(_snapshot, _rules, _branch_id),
    do: ["Добавьте награду, чтобы сравнить выгоду сертификата с правилами сайта."]

  defp product_matches?(%{"product_id" => external_id, "price" => price}, effects, branch_id) do
    product_ids =
      branch_id
      |> Net.list_branch_products()
      |> Enum.filter(fn product ->
        case effects do
          [{:gift, slug, 1}] -> product.slug == slug and price == 0
          [{:price, slug, ^price}] -> product.slug == slug
          _ -> false
        end
      end)
      |> Enum.map(& &1.id)

    product_ids
    |> ProductCrmIds.by_product(:frontpad, branch_id)
    |> Map.values()
    |> Enum.any?(&(&1 == external_id))
  end
end
