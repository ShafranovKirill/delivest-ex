defmodule Delivest.Integrations.Frontpad.PaymentCodes do
  use Ecto.Schema
  import Ecto.Changeset

  @methods [:cash, :card_offline, :online]
  @defaults %{cash: "1", card_offline: "2"}

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    for method <- @methods, do: field(method, :string)
  end

  def methods, do: @methods

  def default(method), do: Map.get(@defaults, method)

  def changeset(codes, attrs) do
    codes
    |> cast(attrs, @methods)
    |> then(
      &Enum.reduce(@methods, &1, fn method, cs -> validate_format(cs, method, ~r/^\d+$/) end)
    )
  end

  def code_for(codes, method) do
    case codes && Map.get(codes, method) do
      code when is_binary(code) and code != "" -> code
      _ -> fallback(codes, method)
    end
  end

  defp fallback(codes, :online), do: code_for(codes, :card_offline)
  defp fallback(_codes, method), do: default(method) || default(:cash)
end
