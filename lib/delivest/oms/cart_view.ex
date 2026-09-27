defmodule Delivest.Oms.CartView do
  @type item :: %{
          product_id: binary(),
          name: String.t(),
          image_url: String.t() | nil,
          price: integer(),
          quantity: integer(),
          total_price: integer()
        }

  @type t :: %__MODULE__{
          id: binary(),
          session_id: String.t() | nil,
          staff_id: binary() | nil,
          branch_id: binary() | nil,
          items: [item()],
          total_quantity: non_neg_integer(),
          total_amount: non_neg_integer()
        }

  defstruct [
    :id,
    :session_id,
    :staff_id,
    :branch_id,
    items: [],
    total_quantity: 0,
    total_amount: 0
  ]
end
