defmodule Delivest.Integrations.Frontpad.Fields do
  def text(nil, _max_length), do: nil

  def text(value, max_length) do
    case value |> to_string() |> String.trim() |> String.slice(0, max_length) do
      "" -> nil
      text -> text
    end
  end

  def digits(nil, max_length), do: text(nil, max_length)

  def digits(value, max_length),
    do: value |> to_string() |> String.replace(~r/\D/, "") |> text(max_length)
end
