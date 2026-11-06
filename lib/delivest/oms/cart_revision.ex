defmodule Delivest.Oms.CartRevision do
  @moduledoc false

  alias Delivest.Oms.Cart

  def from_raw(%Cart{} = cart, catalog_version, items) do
    snapshot = [
      cart.branch_id,
      cart.client_id,
      cart.fulfillment_type,
      cart.promo_code,
      canonical(cart.promo_gifts),
      catalog_version,
      items
      |> Enum.map(fn item ->
        {item.product_id, item.modifier_key, item.quantity, canonical(item.modifiers)}
      end)
      |> Enum.sort()
    ]

    :crypto.hash(:sha256, :erlang.term_to_binary(snapshot))
    |> Base.encode16(case: :lower)
  end

  defp canonical(map) when is_map(map),
    do: map |> Enum.map(fn {key, value} -> {to_string(key), canonical(value)} end) |> Enum.sort()

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(value), do: value
end
