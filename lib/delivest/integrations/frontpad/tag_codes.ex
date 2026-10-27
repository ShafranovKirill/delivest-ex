defmodule Delivest.Integrations.Frontpad.TagCodes do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Oms.OrderSource

  @sources Enum.map(OrderSource.all(), &String.to_atom/1)
  @marks @sources ++ [:paid_online]

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    for mark <- @marks, do: field(mark, :string)
  end

  def sources, do: @sources

  def marks, do: @marks

  def changeset(codes, attrs) do
    codes
    |> cast(attrs, @marks)
    |> then(&Enum.reduce(@marks, &1, fn mark, cs -> validate_format(cs, mark, ~r/^\d+$/) end))
  end

  def codes(nil, _order), do: []

  def codes(%__MODULE__{} = codes, order) do
    [source_code(codes, order.source), paid_code(codes, order.payment_method)]
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp source_code(codes, source) when is_binary(source) do
    case Enum.find(@sources, &(Atom.to_string(&1) == source)) do
      nil -> nil
      mark -> Map.get(codes, mark)
    end
  end

  defp source_code(_codes, _source), do: nil

  defp paid_code(codes, :online), do: codes.paid_online
  defp paid_code(_codes, _method), do: nil
end
