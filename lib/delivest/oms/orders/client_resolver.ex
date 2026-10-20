defmodule Delivest.Oms.Orders.ClientResolver do
  alias Delivest.Identity

  def resolve(attrs, opts \\ []) do
    if valid_phone?(attrs["customer_phone"]),
      do: Identity.resolve_client(attrs, opts),
      else: {:ok, nil}
  end

  defp valid_phone?(phone) when is_binary(phone), do: Regex.match?(Identity.phone_regex(), phone)
  defp valid_phone?(_phone), do: false
end
