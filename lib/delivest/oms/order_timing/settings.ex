defmodule Delivest.Oms.OrderTiming.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :mode, Ecto.Enum, values: [:fixed, :calculated], default: :fixed
    field :kitchen_minutes, :integer, default: 25
    field :packing_minutes, :integer, default: 0
    field :travel_minutes, :integer, default: 35
    field :category_minutes, :map, default: %{}
    field :product_minutes, :map, default: %{}
  end

  def changeset(settings, attrs) do
    attrs = normalize_minutes_maps(attrs)

    settings
    |> cast(attrs, [
      :mode,
      :kitchen_minutes,
      :packing_minutes,
      :travel_minutes,
      :category_minutes,
      :product_minutes
    ])
    |> validate_required([:mode, :kitchen_minutes, :packing_minutes, :travel_minutes])
    |> validate_number(:kitchen_minutes, greater_than: 0, less_than_or_equal_to: 600)
    |> validate_number(:packing_minutes, greater_than_or_equal_to: 0, less_than_or_equal_to: 120)
    |> validate_number(:travel_minutes, greater_than: 0, less_than_or_equal_to: 600)
    |> validate_minutes_map(:category_minutes)
    |> validate_minutes_map(:product_minutes)
  end

  defp normalize_minutes_maps(attrs) when is_map(attrs) do
    Enum.reduce([:category_minutes, :product_minutes], attrs, fn field, acc ->
      key = if Map.has_key?(acc, field), do: field, else: Atom.to_string(field)

      case Map.get(acc, key) do
        values when is_map(values) ->
          normalized =
            Map.new(values, fn {id, minutes} ->
              parsed =
                case minutes do
                  value when is_binary(value) ->
                    case Integer.parse(value) do
                      {number, ""} -> number
                      _ -> value
                    end

                  value ->
                    value
                end

              {id, parsed}
            end)

          Map.put(acc, key, normalized)

        _ ->
          acc
      end
    end)
  end

  defp normalize_minutes_maps(attrs), do: attrs

  defp validate_minutes_map(changeset, field) do
    validate_change(changeset, field, fn ^field, values ->
      if is_map(values) and
           Enum.all?(values, fn {id, minutes} ->
             match?({:ok, _}, Ecto.UUID.cast(id)) and is_integer(minutes) and
               minutes > 0 and minutes <= 600
           end) do
        []
      else
        [{field, "must contain UUID keys and minute values between 1 and 600"}]
      end
    end)
  end
end
