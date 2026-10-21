defmodule Delivest.Promo.Compiled do
  alias Delivest.Promo.{Promotion, Strategy}

  @type t :: %__MODULE__{
          promotion: Promotion.t(),
          strategy: Strategy.t(),
          products: %{String.t() => Delivest.Net.Product.t()}
        }

  defstruct [:promotion, :strategy, products: %{}]

  def product(%__MODULE__{products: products}, slug), do: Map.get(products, slug)

  def product_id(compiled, slug) do
    case product(compiled, slug) do
      %{id: id} -> id
      nil -> nil
    end
  end

  def automatic?(%__MODULE__{promotion: %{kind: kind}}), do: kind == :automatic
end
