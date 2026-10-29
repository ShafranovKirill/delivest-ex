defmodule Delivest.Delivery.Threshold do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field :order_from, Delivest.Money.Type, default: 0
    field :price, Delivest.Money.Type, default: 0
  end

  def changeset(threshold, attrs) do
    threshold
    |> cast(attrs, [:order_from, :price])
    |> validate_required([:order_from, :price])
    |> validate_number(:order_from, greater_than_or_equal_to: 0, less_than: 100_000_000)
    |> validate_number(:price, greater_than_or_equal_to: 0, less_than: 10_000_000)
  end

  def validate_list(changeset, field) do
    thresholds = get_field(changeset, field) || []
    froms = Enum.map(thresholds, & &1.order_from)

    cond do
      length(thresholds) > 10 ->
        add_error(changeset, field, "at most 10 conditions")

      length(Enum.uniq(froms)) != length(froms) ->
        add_error(changeset, field, "order sums repeat")

      true ->
        changeset
    end
  end

  def sort(thresholds), do: Enum.sort_by(thresholds, & &1.order_from)
end
