defmodule Delivest.Geo.NormalizedAddress do
  import Ecto.Changeset

  @fields [:formatted, :fias_id, :postal_code, :district, :geo_precision]

  def fields, do: @fields

  def validate(changeset) do
    changeset
    |> validate_length(:formatted, max: 255)
    |> validate_length(:fias_id, max: 36)
    |> validate_length(:postal_code, max: 10)
    |> validate_length(:district, max: 100)
    |> validate_number(:geo_precision, greater_than_or_equal_to: 0, less_than_or_equal_to: 5)
  end
end
