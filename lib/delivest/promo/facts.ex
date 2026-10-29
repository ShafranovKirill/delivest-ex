defmodule Delivest.Promo.Facts do
  alias Delivest.Promo.{Basket, Context}

  @type t :: %__MODULE__{
          subtotal: non_neg_integer(),
          quantity: non_neg_integer(),
          quantities: %{binary() => pos_integer()},
          fulfillment: atom() | nil,
          time: Time.t(),
          weekday: 1..7
        }

  defstruct [:subtotal, :quantity, :quantities, :fulfillment, :time, :weekday]

  def build(%Basket{} = basket, %Context{} = context) do
    local = DateTime.shift_zone!(context.now, Delivest.LocalTime.timezone(context.branch_id))

    %__MODULE__{
      subtotal: Basket.subtotal(basket),
      quantity: Basket.quantity(basket),
      quantities: Basket.quantities(basket),
      fulfillment: context.fulfillment_type,
      time: DateTime.to_time(local),
      weekday: local |> DateTime.to_date() |> Date.day_of_week()
    }
  end
end
