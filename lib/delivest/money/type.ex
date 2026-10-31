defmodule Delivest.Money.Type do
  use Ecto.Type

  alias Delivest.Money

  def type, do: :integer

  def cast(value) when is_integer(value), do: {:ok, value}
  def cast(value) when is_binary(value), do: Money.parse(value)
  def cast(_value), do: :error

  def load(value) when is_integer(value), do: {:ok, value}
  def load(_value), do: :error

  def dump(value) when is_integer(value), do: {:ok, value}
  def dump(_value), do: :error
end
