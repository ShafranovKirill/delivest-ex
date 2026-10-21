defmodule DelivestWeb.Staff.PromotionLive.ProductSale do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Promo.Dsl
  alias Delivest.Promo.Effects.ProductPrices
  alias DelivestWeb.Staff.PromotionLive.RulesBuilder

  @modes ~w(percent amount price)
  @name_limit 100

  defstruct products: [], mode: "percent", value: ""

  def modes, do: @modes

  def from_params(params) when is_map(params) do
    products = params |> Map.get("products", []) |> List.wrap() |> Enum.reject(&blank?/1)
    added = Map.get(params, "add", "")

    %__MODULE__{
      products: if(blank?(added) or added in products, do: products, else: products ++ [added]),
      mode: if(params["mode"] in @modes, do: params["mode"], else: "percent"),
      value: String.trim(params["value"] || "")
    }
  end

  def from_params(_params), do: %__MODULE__{}

  def remove_product(sale, slug), do: %{sale | products: List.delete(sale.products, slug)}

  def to_rules(sale), do: RulesBuilder.to_rules(%RulesBuilder{effects: effects(sale)})

  def error(%__MODULE__{products: []}, _prices), do: gettext("Choose at least one product")

  def error(sale, prices) do
    sale |> effects() |> Enum.find_value(&RulesBuilder.effect_error/1) ||
      no_discount_error(sale, prices)
  end

  def new_prices(sale, prices) do
    case Dsl.parse(to_rules(sale)) do
      {:ok, strategy} ->
        for effect <- strategy.effects,
            slug <- ProductPrices.slugs(effect),
            {:ok, base} <- [Map.fetch(prices, slug)],
            into: %{},
            do: {slug, ProductPrices.unit_price(effect, base)}

      {:error, _errors} ->
        %{}
    end
  end

  def default_name(%__MODULE__{products: []}, _names), do: nil

  def default_name(sale, names) do
    products = Enum.map_join(sale.products, ", ", &Map.get(names, &1, &1))
    String.slice(gettext("Sale: %{products}", products: products), 0, @name_limit)
  end

  defp no_discount_error(sale, prices) do
    if Enum.any?(new_prices(sale, prices), fn {slug, price} -> price >= prices[slug] end),
      do: gettext("The new price must be lower than the current one")
  end

  defp effects(%__MODULE__{mode: "price"} = sale),
    do: Enum.map(sale.products, &%{"type" => "price", "product" => &1, "price" => sale.value})

  defp effects(sale) do
    [
      %{
        "type" => sale.mode,
        "value" => sale.value,
        "target" => "products",
        "products" => sale.products,
        "cap" => ""
      }
    ]
  end

  defp blank?(value), do: value in [nil, ""]
end
