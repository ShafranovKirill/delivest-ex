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

  defstruct [:branch_id, :client_id, :fulfillment_type, :code, :now, :except_order_id]

  def new(attrs) do
    attrs = Map.new(attrs)

    %__MODULE__{
      branch_id: attrs[:branch_id],
      client_id: attrs[:client_id],
      fulfillment_type: fulfillment(attrs[:fulfillment_type]),
      code: blank_to_nil(attrs[:code]),
      now: attrs[:now] || DateTime.utc_now(:second),
      except_order_id: attrs[:except_order_id]
    }
  end

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
