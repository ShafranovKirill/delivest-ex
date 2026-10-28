defmodule Delivest.Oms.Orders.Search do
  import Ecto.Query, warn: false

  @min_digits 3

  def apply(query, term) do
    case term |> String.trim() |> String.trim_leading("#") do
      "" ->
        query

      term ->
        query
        |> join(:left, [o], c in assoc(o, :client), as: :search_client)
        |> where(^matches(term))
    end
  end

  defp matches(term) do
    pattern = "%" <> escape(term) <> "%"

    dynamic(
      [o, search_client: c],
      ^phone_match(digits(term)) or ilike(o.number, ^pattern) or ilike(c.name, ^pattern) or
        ilike(fragment("?->>'formatted'", o.address), ^pattern) or
        ilike(fragment("?->>'street'", o.address), ^pattern)
    )
  end

  defp phone_match(digits) when byte_size(digits) < @min_digits, do: dynamic(false)

  defp phone_match(digits) do
    pattern = "%" <> digits <> "%"

    dynamic(
      [search_client: c],
      like(fragment("regexp_replace(?, '\\D', '', 'g')", c.phone), ^pattern)
    )
  end

  defp digits(term) do
    case String.replace(term, ~r/\D/, "") do
      "8" <> rest when byte_size(rest) == 10 -> "7" <> rest
      digits -> digits
    end
  end

  defp escape(term), do: String.replace(term, ~r/[\\%_]/, "\\\\\\0")
end
