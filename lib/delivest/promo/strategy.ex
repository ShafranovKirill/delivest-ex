defmodule Delivest.Promo.Strategy do
  @type slug :: String.t()
  @type target :: :cart | {:products, [slug()]}

  @type condition ::
          {:and, condition(), condition()}
          | {:or, condition(), condition()}
          | {:not, condition()}
          | {:subtotal, atom(), non_neg_integer()}
          | {:quantity, atom(), non_neg_integer()}
          | {:has, slug(), pos_integer()}
          | {:fulfillment, [atom()]}
          | {:time, Time.t(), Time.t()}
          | {:weekday, [1..7]}

  @type effect ::
          {:percent, 1..100, target(), pos_integer() | nil}
          | {:amount, pos_integer(), target()}
          | {:gift, slug(), pos_integer()}
          | {:price, slug(), non_neg_integer()}

  @type t :: %__MODULE__{condition: condition() | nil, effects: [effect()]}

  defstruct condition: nil, effects: []

  def unconditional?(%__MODULE__{condition: nil}), do: true
  def unconditional?(%__MODULE__{}), do: false

  def slugs(%__MODULE__{condition: condition, effects: effects}) do
    (condition_slugs(condition) ++ Enum.flat_map(effects, &effect_slugs/1)) |> Enum.uniq()
  end

  defp condition_slugs({op, a, b}) when op in [:and, :or],
    do: condition_slugs(a) ++ condition_slugs(b)

  defp condition_slugs({:not, a}), do: condition_slugs(a)
  defp condition_slugs({:has, slug, _quantity}), do: [slug]
  defp condition_slugs(_condition), do: []

  defp effect_slugs({:percent, _value, target, _cap}), do: target_slugs(target)
  defp effect_slugs({:amount, _value, target}), do: target_slugs(target)
  defp effect_slugs({:gift, slug, _quantity}), do: [slug]
  defp effect_slugs({:price, slug, _price}), do: [slug]

  defp target_slugs({:products, slugs}), do: slugs
  defp target_slugs(:cart), do: []
end
