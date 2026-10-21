defmodule Delivest.Promo.Dsl do
  alias Delivest.Promo.Dsl.{Error, Semantics, Syntax}
  alias Delivest.Promo.Strategy

  @spec parse(String.t() | nil) :: {:ok, Strategy.t()} | {:error, [Error.t()]}
  def parse(text) when is_binary(text) do
    with {:ok, ast} <- Syntax.parse(text) do
      Semantics.build(ast)
    end
  end

  def parse(_text), do: Syntax.parse("")
end
