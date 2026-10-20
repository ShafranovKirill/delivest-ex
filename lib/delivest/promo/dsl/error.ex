defmodule Delivest.Promo.Dsl.Error do
  @type t :: %__MODULE__{
          line: pos_integer() | nil,
          column: pos_integer() | nil,
          message: String.t()
        }

  defstruct [:line, :column, :message]

  def at({line, column}, message), do: %__MODULE__{line: line, column: column, message: message}
  def at(nil, message), do: %__MODULE__{message: message}

  def to_string(%__MODULE__{line: nil, message: message}), do: message

  def to_string(%__MODULE__{line: line, column: column, message: message}),
    do: "#{line}:#{column} #{message}"
end
