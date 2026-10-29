defmodule Delivest.Identity.Phone do
  @spec normalize(term()) :: String.t() | nil
  def normalize(phone) when is_binary(phone) do
    case String.replace(phone, ~r/\D/, "") do
      "8" <> <<rest::binary-size(10)>> -> "+7" <> rest
      "7" <> <<rest::binary-size(10)>> -> "+7" <> rest
      <<rest::binary-size(10)>> -> "+7" <> rest
      _ -> nil
    end
  end

  def normalize(_phone), do: nil

  @spec split(term()) :: {String.t() | nil, String.t() | nil}
  def split(phone) when is_binary(phone) do
    case Regex.split(~r/\s*(?:,|;|#|доб\.?|ext\.?|x)\s*/iu, String.trim(phone), parts: 2) do
      [number, ext] -> {e164(number), digits(ext)}
      [number] -> {e164(number), nil}
    end
  end

  def split(_phone), do: {nil, nil}

  defp e164(number) do
    case normalize(number) do
      nil -> number |> digits() |> then(&(&1 && "+" <> &1))
      phone -> phone
    end
  end

  defp digits(value) do
    case String.replace(value, ~r/\D/, "") do
      "" -> nil
      digits -> digits
    end
  end
end
