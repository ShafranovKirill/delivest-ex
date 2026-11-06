defmodule Delivest.Promo.Context do
  @fulfillments %{"delivery" => :delivery, "pickup" => :pickup, "dine_in" => :dine_in}

  @type t :: %__MODULE__{
          branch_id: binary() | nil,
          client_id: binary() | nil,
          fulfillment_type: atom() | nil,
          code: String.t() | nil,
          now: DateTime.t(),
          except_order_id: binary() | nil
        }

  defstruct [
    :branch_id,
    :client_id,
    :fulfillment_type,
    :code,
    :now,
    :except_order_id,
    :compiled_promotions,
    :product_snapshot,
    :catalog_version,
    promo_gifts: %{}
  ]

  def new(attrs) do
    attrs = Map.new(attrs)

    %__MODULE__{
      promo_gifts: normalize_gifts(attrs[:promo_gifts]),
      branch_id: attrs[:branch_id],
      client_id: attrs[:client_id],
      fulfillment_type: fulfillment(attrs[:fulfillment_type]),
      code: blank_to_nil(attrs[:code]),
      now: attrs[:now] || DateTime.utc_now(:second),
      except_order_id: attrs[:except_order_id],
      compiled_promotions: attrs[:compiled_promotions],
      product_snapshot: attrs[:product_snapshot],
      catalog_version: attrs[:catalog_version]
    }
  end

  def normalize_gifts(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, ids}, acc ->
      with {:ok, key} <- Ecto.UUID.cast(key),
           true <- is_list(ids) and ids != [],
           true <- Enum.all?(ids, &match?({:ok, _}, Ecto.UUID.cast(&1))) do
        Map.put(
          acc,
          key,
          ids
          |> Enum.map(fn id ->
            {:ok, uuid} = Ecto.UUID.cast(id)
            uuid
          end)
          |> Enum.uniq()
        )
      else
        _ -> acc
      end
    end)
  end

  def normalize_gifts(_), do: %{}

  def fulfillment(value) when is_atom(value) and not is_nil(value),
    do: if(value in Map.values(@fulfillments), do: value)

  def fulfillment(value) when is_binary(value), do: Map.get(@fulfillments, value)
  def fulfillment(_value), do: nil

  defp blank_to_nil(code) when is_binary(code) do
    case Delivest.Promo.PromoCode.normalize(code) do
      "" -> nil
      code -> code
    end
  end

  defp blank_to_nil(_code), do: nil
end
