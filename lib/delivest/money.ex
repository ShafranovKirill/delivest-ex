defmodule Delivest.Money do
  @type t :: integer()

  @spec format(t() | float() | nil) :: String.t()
  def format(nil), do: "0 ₽"
  def format(amount) when is_float(amount), do: format(round(amount))
  def format(amount) when is_integer(amount), do: render(amount, &group/1) <> " ₽"

  @spec input(t() | String.t() | nil) :: String.t() | nil
  def input(nil), do: nil
  def input(value) when is_binary(value), do: value

  def input(amount) when is_integer(amount), do: render(amount, &Integer.to_string/1)

  defp render(amount, rubles) do
    rubles = amount |> abs() |> div(100) |> rubles.()
    sign = if amount < 0, do: "-", else: ""

    case amount |> abs() |> rem(100) do
      0 -> sign <> rubles
      kopecks -> sign <> rubles <> "," <> String.pad_leading(Integer.to_string(kopecks), 2, "0")
    end
  end

  @spec parse(String.t() | t() | nil) :: {:ok, t()} | :error
  def parse(value) when is_integer(value), do: {:ok, value}

  def parse(value) when is_binary(value) do
    normalized =
      value
      |> String.replace(~r/[\s ₽]/u, "")
      |> String.replace(",", ".")

    case Regex.run(~r/^(-?)(\d+)(?:\.(\d{1,2}))?$/, normalized) do
      [_, sign, rubles] -> signed(sign, String.to_integer(rubles) * 100)
      [_, sign, rubles, kopecks] -> signed(sign, kopecks(rubles, kopecks))
      nil -> :error
    end
  end

  def parse(_value), do: :error

  @spec from_rubles(number() | Decimal.t()) :: t()
  def from_rubles(value) when is_integer(value), do: value * 100
  def from_rubles(value) when is_float(value), do: round(value * 100)

  def from_rubles(%Decimal{} = value),
    do: value |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()

  @spec to_rubles(t()) :: integer() | float()
  def to_rubles(amount) when rem(amount, 100) == 0, do: div(amount, 100)
  def to_rubles(amount), do: amount / 100

  @spec percent(t(), number()) :: t()
  def percent(amount, percent), do: div(amount * percent * 2 + 100, 200)

  @spec round_up(t(), pos_integer()) :: t()
  def round_up(amount, step) do
    case rem(amount, step) do
      0 -> amount
      rest -> amount - rest + step
    end
  end

  @spec distribute(non_neg_integer(), [non_neg_integer()]) :: [non_neg_integer()]
  def distribute(amount, weights) do
    case Enum.sum(weights) do
      0 -> Enum.map(weights, fn _ -> 0 end)
      total -> largest_remainder(min(amount, total), weights, total)
    end
  end

  @spec split_unit_price(non_neg_integer(), pos_integer()) :: [{non_neg_integer(), pos_integer()}]
  def split_unit_price(total, quantity) do
    unit = div(total, quantity)
    extra = rem(total, quantity)

    Enum.reject([{unit + 1, extra}, {unit, quantity - extra}], fn {_price, count} ->
      count == 0
    end)
  end

  defp kopecks(rubles, kopecks),
    do: String.to_integer(rubles) * 100 + String.to_integer(String.pad_trailing(kopecks, 2, "0"))

  defp signed("-", amount), do: {:ok, -amount}
  defp signed(_sign, amount), do: {:ok, amount}

  defp group(rubles) do
    rubles
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(" ", &Enum.join/1)
    |> String.reverse()
  end

  defp largest_remainder(amount, weights, total) do
    shares = Enum.map(weights, &div(amount * &1, total))

    bumped =
      weights
      |> Enum.with_index()
      |> Enum.sort_by(fn {weight, index} -> {-rem(amount * weight, total), index} end)
      |> Enum.take(amount - Enum.sum(shares))
      |> MapSet.new(&elem(&1, 1))

    shares
    |> Enum.with_index()
    |> Enum.map(fn {share, index} ->
      if MapSet.member?(bumped, index), do: share + 1, else: share
    end)
  end
end
