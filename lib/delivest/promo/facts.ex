defmodule Delivest.Promo.Facts do
  alias Delivest.Promo.{Basket, Context, FirstOrder}

  @type t :: %__MODULE__{
          subtotal: non_neg_integer(),
          quantity: non_neg_integer(),
          quantities: %{binary() => pos_integer()},
          fulfillment: atom() | nil,
          time: Time.t(),
          weekday: 1..7,
          first_order: boolean(),
          authenticated_client?: boolean()
        }

  defstruct [
    :subtotal,
    :quantity,
    :quantities,
    :fulfillment,
    :time,
    :weekday,
    :first_order,
    :authenticated_client?
  ]

  def build(%Basket{} = basket, %Context{} = context, first_order_condition? \\ false) do
    local = DateTime.shift_zone!(context.now, Delivest.LocalTime.timezone(context.branch_id))

    %__MODULE__{
      subtotal: Basket.subtotal(basket),
      quantity: Basket.quantity(basket),
      quantities: Basket.quantities(basket),
      fulfillment: context.fulfillment_type,
      time: DateTime.to_time(local),
      weekday: local |> DateTime.to_date() |> Date.day_of_week(),
      authenticated_client?:
        not is_nil(context.client_id) and context.client_id == context.authenticated_client_id,
      first_order:
        first_order_condition? and
          not is_nil(context.client_id) and
          context.client_id == context.authenticated_client_id and
          FirstOrder.eligible?(
            context.branch_id,
            context.client_id,
            context.source,
            context.except_order_id
          )
    }
  end
end
