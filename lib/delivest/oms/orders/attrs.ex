defmodule Delivest.Oms.Orders.Attrs do
  alias Delivest.Oms.Orders.Filter

  @blank_phones ["", "+7"]

  def normalize(attrs) do
    attrs
    |> Filter.normalize_params()
    |> drop_blank_phone()
  end

  defp drop_blank_phone(%{"customer_phone" => phone} = attrs) when is_binary(phone) do
    if String.trim(phone) in @blank_phones, do: Map.delete(attrs, "customer_phone"), else: attrs
  end

  defp drop_blank_phone(attrs), do: attrs
end
