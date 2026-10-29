defmodule Delivest.Promo.Dsl.Semantics do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Promo.Dsl.Error
  alias Delivest.Promo.Strategy

  @fulfillments %{"delivery" => :delivery, "pickup" => :pickup, "dine_in" => :dine_in}
  @weekdays %{"mon" => 1, "tue" => 2, "wed" => 3, "thu" => 4, "fri" => 5, "sat" => 6, "sun" => 7}
  @max_quantity 99

  def build({condition, effects}) do
    with_errors(condition(condition), all(effects, &effect/1), fn condition, effects ->
      %Strategy{condition: condition, effects: effects}
    end)
  end

  defp condition(nil), do: {:ok, nil}

  defp condition({op, a, b}) when op in [:and, :or],
    do: with_errors(condition(a), condition(b), &{op, &1, &2})

  defp condition({:not, a}), do: map(condition(a), &{:not, &1})
  defp condition({:subtotal, op, value}), do: {:ok, {:subtotal, op, value}}
  defp condition({:quantity, op, value}), do: {:ok, {:quantity, op, value}}

  defp condition({:has, {slug, location}, quantity}),
    do: map(quantity(quantity, location), &{:has, slug(slug), &1})

  defp condition({:fulfillment, idents}),
    do: map(all(idents, &lookup(&1, @fulfillments, gettext("fulfillment"))), &{:fulfillment, &1})

  defp condition({:weekday, idents}),
    do: map(all(idents, &lookup(&1, @weekdays, gettext("weekday"))), &{:weekday, &1})

  defp condition({:time, from, to}) do
    with_errors(clock(from), clock(to), fn from, to -> {:time, from, to} end)
    |> reject_empty_window(from)
  end

  defp effect({:percent, {value, location}, target, cap}) do
    with {:ok, value} <- range(value, 1..100, location, gettext("Percent must be from 1 to 100")),
         {:ok, cap} <- cap(cap, target) do
      {:ok, {:percent, value, target(target), cap}}
    end
  end

  defp effect({:amount, {value, location}, target}) do
    map(sum(value, location), &{:amount, &1, target(target)})
  end

  defp effect({:gift, {slug, location}, quantity}),
    do: map(quantity(quantity, location), &{:gift, slug(slug), &1})

  defp effect({:price, {slug, _location}, price}), do: {:ok, {:price, slug(slug), price}}

  defp cap(nil, _target), do: {:ok, nil}

  defp cap({value, location}, :cart), do: sum(value, location)

  defp cap({_value, location}, _target),
    do: {:error, [Error.at(location, gettext("«max» works only for a cart discount"))]}

  defp target(:cart), do: :cart

  defp target({:products, slugs}),
    do: {:products, Enum.map(slugs, fn {slug, _} -> slug(slug) end)}

  defp quantity(quantity, location),
    do: range(quantity, 1..@max_quantity, location, gettext("Quantity must be from 1 to 99"))

  defp sum(value, location),
    do: range(value, 1..100_000_000, location, gettext("Value must be positive"))

  defp range(value, range, location, message) do
    if value in range, do: {:ok, value}, else: {:error, [Error.at(location, message)]}
  end

  defp lookup({ident, location}, known, kind) do
    case Map.fetch(known, List.to_string(ident)) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        message =
          gettext("Unknown %{kind} «%{value}», expected: %{known}",
            kind: kind,
            value: List.to_string(ident),
            known: known |> Map.keys() |> Enum.join(", ")
          )

        {:error, [Error.at(location, message)]}
    end
  end

  defp clock({chars, location}) do
    with [hours, minutes] <- chars |> List.to_string() |> String.split(":"),
         {:ok, time} <- Time.new(String.to_integer(hours), String.to_integer(minutes), 0) do
      {:ok, time}
    else
      _ ->
        {:error,
         [Error.at(location, gettext("Invalid time «%{time}»", time: List.to_string(chars)))]}
    end
  end

  defp reject_empty_window({:ok, {:time, same, same}}, {_chars, location}),
    do: {:error, [Error.at(location, gettext("Time window is empty"))]}

  defp reject_empty_window(result, _from), do: result

  defp slug(chars), do: chars |> List.to_string() |> String.trim()

  defp all(items, fun) do
    items
    |> Enum.map(fun)
    |> Enum.reduce({:ok, []}, fn
      {:ok, value}, {:ok, acc} -> {:ok, [value | acc]}
      {:ok, _value}, {:error, errors} -> {:error, errors}
      {:error, new}, {:ok, _acc} -> {:error, new}
      {:error, new}, {:error, errors} -> {:error, errors ++ new}
    end)
    |> map(&Enum.reverse/1)
  end

  defp with_errors({:ok, a}, {:ok, b}, fun), do: {:ok, fun.(a, b)}
  defp with_errors({:error, a}, {:error, b}, _fun), do: {:error, a ++ b}
  defp with_errors({:error, a}, _b, _fun), do: {:error, a}
  defp with_errors(_a, {:error, b}, _fun), do: {:error, b}

  defp map({:ok, value}, fun), do: {:ok, fun.(value)}
  defp map(error, _fun), do: error
end
