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
end
