defmodule Delivest.Pos do
  import Ecto.Query

  alias Delivest.{Oms, Repo}
  alias Delivest.Identity.{Branch, Staff}
  alias Delivest.Integrations.Crm
  alias Delivest.Oms.{Order, Orders}

  @types ~w(dine_in pickup)
  @methods %{"cash" => "cash", "card" => "card_offline"}

  def available?(%Branch{} = branch), do: not Crm.own_pos?(branch)

  def cart(%Staff{id: staff_id}, branch_id),
    do: Oms.get_or_create_cart(session_id: "pos:#{staff_id}", branch_id: branch_id)

  def checkout(%Staff{} = staff, cart, %{"fulfillment_type" => type, "method" => method} = params)
      when type in @types and is_map_key(@methods, method) do
    by = {:staff, staff}

    %{
      "cart_id" => cart.id,
      "branch_id" => cart.branch_id,
      "fulfillment_type" => type,
      "payment_method" => Map.fetch!(@methods, method),
      "cash_given" => if(method == "cash", do: params["cash_given"]),
      "staff_id" => staff.id
    }
    |> Oms.create_order(actor: staff, source: "pos", collect: by, advance: {:accepted, by})
  end

  def checkout(_staff, _cart, _params), do: {:error, :invalid_checkout}

  def change(total, cash_given) when is_integer(cash_given) and cash_given >= total,
    do: cash_given - total

  def change(_total, _cash_given), do: nil

  def ready(branch_id) do
    Repo.all(
      from(o in Order,
        where: o.branch_id == ^branch_id and is_nil(o.deleted_at),
        where: o.fulfillment_type in [:dine_in, :pickup] and o.status == :ready,
        order_by: [asc: o.updated_at]
      )
    )
  end

  def hand_out(%Staff{} = staff, branch_id, order_id) do
    case Orders.get_order(order_id) do
      %Order{branch_id: ^branch_id, status: :ready} = order ->
        Orders.advance_order(order, :completed, {:staff, staff})

      _other ->
        {:error, :not_found}
    end
  end
end
