defmodule Delivest.Oms.Orders.Assembler do
  alias Delivest.Oms.Order

  def changeset(%Order{} = order, attrs, %{cart: cart, lines: lines, client_id: client_id}) do
    params =
      Map.merge(attrs, %{
        "cart_id" => cart.id,
        "branch_id" => cart.branch_id,
        "client_id" => client_id,
        "total_amount" => lines.total_amount
      })

    order
    |> Order.changeset(params)
    |> Ecto.Changeset.put_assoc(:items, lines.items)
  end
end
