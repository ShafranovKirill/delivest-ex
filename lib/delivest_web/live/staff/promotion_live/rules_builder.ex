defmodule DelivestWeb.Staff.PromotionLive.RulesBuilder do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Money
  alias Delivest.Promo.Dsl

  @condition_types ~w(subtotal quantity has fulfillment time weekday)
  @effect_types ~w(percent amount gift price)
  @ops ~w(>= > <= < =)
  @fulfillments ~w(delivery pickup dine_in)
  @weekdays ~w(mon tue wed thu fri sat sun)

  defstruct match: "all", conditions: [], effects: []

  def condition_types, do: @condition_types
  def effect_types, do: @effect_types
  def ops, do: @ops
  def fulfillments, do: @fulfillments
  def weekdays, do: @weekdays

  def new, do: %__MODULE__{effects: [blank_effect("percent")]}

  def from_rules(rules) do
    with {:ok, strategy} <- Dsl.parse(rules),
         {:ok, match, conditions} <- flatten(strategy.condition) do
      {:ok,
       %__MODULE__{
         match: match,
         conditions: Enum.map(conditions, &condition_row/1),
         effects: Enum.map(strategy.effects, &effect_row/1)
       }}
    else
      _ -> :error
    end
  end

  def from_params(params) when is_map(params) do
    %__MODULE__{
      match: if(params["match"] == "any", do: "any", else: "all"),
      conditions: params |> rows("conditions") |> Enum.map(&normalize_condition/1),
      effects: params |> rows("effects") |> Enum.map(&normalize_effect/1)
    }
  end

  def from_params(_params), do: %__MODULE__{}

  def add_condition(builder, type) when type in @condition_types,
    do: %{builder | conditions: builder.conditions ++ [blank_condition(type)]}

  def add_condition(builder, _type), do: builder

  def add_effect(builder, type) when type in @effect_types,
    do: %{builder | effects: builder.effects ++ [blank_effect(type)]}

  def add_effect(builder, _type), do: builder

  def remove_condition(builder, index),
    do: %{builder | conditions: List.delete_at(builder.conditions, index)}

  def remove_effect(builder, index),
    do: %{builder | effects: List.delete_at(builder.effects, index)}

  def remove_product(builder, index, slug) do
    effects =
      List.update_at(builder.effects, index, fn row ->
        Map.update(row, "products", [], &List.delete(&1, slug))
      end)

    %{builder | effects: effects}
  end

  def to_rules(%__MODULE__{} = builder) do
    effects =
      builder.effects |> Enum.filter(&(effect_error(&1) == nil)) |> Enum.map(&effect_text/1)

    conditions =
      builder.conditions
      |> Enum.filter(&(condition_error(&1) == nil))
      |> Enum.map(&condition_text/1)

    joiner = if builder.match == "any", do: "\n  or ", else: "\n  and "

    case {conditions, effects} do
      {_conditions, []} ->
        ""

      {[], effects} ->
        "then " <> Enum.join(effects, ",\n     ")

      {conditions, effects} ->
        "when #{Enum.join(conditions, joiner)}\nthen #{Enum.join(effects, ",\n     ")}"
    end
  end

  def errors(%__MODULE__{} = builder) do
    conditions = indexed_errors(builder.conditions, &condition_error/1, :condition)
    effects = indexed_errors(builder.effects, &effect_error/1, :effect)
    Map.merge(conditions, effects)
  end

  def condition_error(%{"type" => "subtotal", "value" => value}),
    do: unless(money(value, 0), do: gettext("Enter an amount"))

  def condition_error(%{"type" => "quantity", "value" => value}),
    do: unless(integer(value, 0), do: gettext("Enter a number of items"))

  def condition_error(%{"type" => "has"} = row), do: product_error(row, "count")

  def condition_error(%{"type" => type, "values" => values}) when type in ~w(fulfillment weekday),
    do: if(values == [], do: gettext("Choose at least one option"))

  def condition_error(%{"type" => "time", "from" => from, "to" => to}) do
    cond do
      !clock?(from) or !clock?(to) -> gettext("Enter both times")
      from == to -> gettext("Time window is empty")
      true -> nil
    end
  end

  def effect_error(%{"type" => "percent", "value" => value} = row) do
    cond do
      !integer(value, 1, 100) ->
        gettext("Percent must be from 1 to 100")

      row["target"] == "cart" and row["cap"] != "" and !money(row["cap"], 1) ->
        gettext("Limit must be a positive amount")

      true ->
        target_error(row)
    end
  end

  def effect_error(%{"type" => "amount", "value" => value} = row),
    do: if(money(value, 1), do: target_error(row), else: gettext("Enter an amount"))

  def effect_error(%{"type" => "gift"} = row), do: product_error(row, "count")

  def effect_error(%{"type" => "price", "price" => price} = row) do
    cond do
      blank?(row["product"]) -> gettext("Choose a product")
      !money(price, 0) -> gettext("Enter a price")
      true -> nil
    end
  end

  defp product_error(row, count_key) do
    cond do
      blank?(row["product"]) -> gettext("Choose a product")
      !integer(row[count_key], 1, 99) -> gettext("Quantity must be from 1 to 99")
      true -> nil
    end
  end

  defp target_error(%{"target" => "products", "products" => []}),
    do: gettext("Choose at least one product")

  defp target_error(_row), do: nil

  defp indexed_errors(rows, fun, kind) do
    rows
    |> Enum.with_index()
    |> Enum.flat_map(fn {row, index} ->
      case fun.(row) do
        nil -> []
        message -> [{{kind, index}, message}]
      end
    end)
    |> Map.new()
  end

  defp condition_text(%{"type" => "subtotal", "op" => op, "value" => value}),
    do: "subtotal #{op} #{sum(value)}"

  defp condition_text(%{"type" => "quantity", "op" => op, "value" => value}),
    do: "quantity #{op} #{trim(value)}"

  defp condition_text(%{"type" => "has", "product" => product, "count" => count}),
    do: ~s(has "#{product}" x#{trim(count)})

  defp condition_text(%{"type" => type, "values" => values})
       when type in ~w(fulfillment weekday),
       do: "#{type} in (#{Enum.join(values, ", ")})"

  defp condition_text(%{"type" => "time", "from" => from, "to" => to}),
    do: "time #{from}..#{to}"

  defp effect_text(%{"type" => "percent", "value" => value} = row) do
    cap = if row["target"] == "cart" and row["cap"] != "", do: " max #{sum(row["cap"])}"
    "discount #{trim(value)}%#{target_text(row)}#{cap}"
  end

  defp effect_text(%{"type" => "amount", "value" => value} = row),
    do: "discount #{sum(value)} rub#{target_text(row)}"

  defp effect_text(%{"type" => "gift", "product" => product, "count" => count}),
    do: ~s(gift "#{product}" x#{trim(count)})

  defp effect_text(%{"type" => "price", "product" => product, "price" => price}),
    do: ~s(price "#{product}" #{sum(price)})

  defp target_text(%{"target" => "products", "products" => [slug]}), do: ~s( on "#{slug}")

  defp target_text(%{"target" => "products", "products" => slugs}),
    do: " on (" <> Enum.map_join(slugs, ", ", &~s("#{&1}")) <> ")"

  defp target_text(_row), do: ""

  defp blank_condition("subtotal"), do: %{"type" => "subtotal", "op" => ">=", "value" => ""}
  defp blank_condition("quantity"), do: %{"type" => "quantity", "op" => ">=", "value" => ""}
  defp blank_condition("has"), do: %{"type" => "has", "product" => "", "count" => "1"}
  defp blank_condition("fulfillment"), do: %{"type" => "fulfillment", "values" => []}
  defp blank_condition("time"), do: %{"type" => "time", "from" => "", "to" => ""}
  defp blank_condition("weekday"), do: %{"type" => "weekday", "values" => []}

  defp blank_effect("percent"),
    do: %{"type" => "percent", "value" => "", "target" => "cart", "products" => [], "cap" => ""}

  defp blank_effect("amount"),
    do: %{"type" => "amount", "value" => "", "target" => "cart", "products" => []}

  defp blank_effect("gift"), do: %{"type" => "gift", "product" => "", "count" => "1"}
  defp blank_effect("price"), do: %{"type" => "price", "product" => "", "price" => ""}

  defp normalize_condition(row) do
    row = type_row(row, &blank_condition/1, @condition_types)

    case row do
      %{"op" => op} when op not in @ops -> Map.put(row, "op", ">=")
      %{"values" => values} -> Map.put(row, "values", Enum.reject(List.wrap(values), &blank?/1))
      row -> row
    end
  end

  defp normalize_effect(row) do
    row = type_row(row, &blank_effect/1, @effect_types)

    case row do
      %{"products" => products} ->
        added = Map.get(row, "add", "")
        products = Enum.reject(products, &blank?/1)
        products = if blank?(added) or added in products, do: products, else: products ++ [added]
        row |> Map.delete("add") |> Map.put("products", products)

      row ->
        row
    end
  end

  defp type_row(row, blank_fun, types) do
    type = if row["type"] in types, do: row["type"], else: hd(types)
    blank = blank_fun.(type)

    row =
      row
      |> Map.take(Map.keys(blank) ++ ["add"])
      |> Enum.map(fn
        {key, value} when is_binary(value) -> {key, String.trim(value)}
        pair -> pair
      end)
      |> Map.new()

    blank |> Map.merge(row) |> Map.put("type", type)
  end

  defp rows(params, key) do
    params
    |> Map.get(key, %{})
    |> Enum.sort_by(fn {index, _row} -> String.to_integer(index) end)
    |> Enum.map(fn {_index, row} -> row end)
  end

  defp flatten(nil), do: {:ok, "all", []}
  defp flatten({:or, _a, _b} = condition), do: chain(condition, :or, "any")
  defp flatten(condition), do: chain(condition, :and, "all")

  defp chain(condition, op, match) do
    case atoms(condition, op) do
      {:ok, atoms} -> {:ok, match, atoms}
      :error -> :error
    end
  end

  defp atoms({op, a, b}, op) do
    with {:ok, left} <- atoms(a, op), {:ok, right} <- atoms(b, op), do: {:ok, left ++ right}
  end

  defp atoms({op, _a, _b}, _expected) when op in [:and, :or], do: :error
  defp atoms({:not, _a}, _expected), do: :error
  defp atoms(atom, _expected), do: {:ok, [atom]}

  defp condition_row({:subtotal, op, value}),
    do: %{"type" => "subtotal", "op" => to_string(op), "value" => Money.input(value)}

  defp condition_row({:quantity, op, value}),
    do: %{"type" => "quantity", "op" => to_string(op), "value" => to_string(value)}

  defp condition_row({:has, slug, count}),
    do: %{"type" => "has", "product" => slug, "count" => to_string(count)}

  defp condition_row({:fulfillment, types}),
    do: %{"type" => "fulfillment", "values" => Enum.map(types, &to_string/1)}

  defp condition_row({:weekday, days}),
    do: %{"type" => "weekday", "values" => Enum.map(days, &Enum.at(@weekdays, &1 - 1))}

  defp condition_row({:time, from, to}),
    do: %{"type" => "time", "from" => clock(from), "to" => clock(to)}

  defp effect_row({:percent, value, target, cap}) do
    "percent"
    |> blank_effect()
    |> Map.merge(%{"value" => to_string(value), "cap" => if(cap, do: Money.input(cap), else: "")})
    |> Map.merge(target_row(target))
  end

  defp effect_row({:amount, value, target}),
    do:
      "amount"
      |> blank_effect()
      |> Map.put("value", Money.input(value))
      |> Map.merge(target_row(target))

  defp effect_row({:gift, slug, count}),
    do: %{"type" => "gift", "product" => slug, "count" => to_string(count)}

  defp effect_row({:price, slug, price}),
    do: %{"type" => "price", "product" => slug, "price" => Money.input(price)}

  defp target_row(:cart), do: %{"target" => "cart", "products" => []}
  defp target_row({:products, slugs}), do: %{"target" => "products", "products" => slugs}

  defp clock(time), do: Calendar.strftime(time, "%H:%M")

  defp clock?(value) when is_binary(value), do: Regex.match?(~r/^\d{1,2}:\d{2}$/, value)
  defp clock?(_value), do: false

  defp integer(value, min, max \\ 1_000_000) do
    case Integer.parse(trim(value)) do
      {number, ""} -> number >= min and number <= max
      _ -> false
    end
  end

  defp money(value, min) do
    case Money.parse(trim(value)) do
      {:ok, amount} -> amount >= min * 100 and amount <= 100_000_000
      :error -> false
    end
  end

  defp sum(value) do
    {:ok, amount} = Money.parse(trim(value))
    Money.input(amount) |> String.replace(",", ".")
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: to_string(value)

  defp blank?(value), do: value in [nil, ""]
end
