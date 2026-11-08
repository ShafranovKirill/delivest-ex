defmodule Delivest.Promo.FirstOrder do
  @moduledoc false

  import Ecto.Query

  alias Delivest.Oms.Order
  alias Delivest.Promo.Redemption
  alias Delivest.Repo

  def eligible?(branch_id, client_id, source, except_order_id \\ nil)

  def eligible?(branch_id, client_id, "app", except_order_id)
      when not is_nil(branch_id) and not is_nil(client_id) do
    query =
      from order in Order,
        where:
          order.branch_id == ^branch_id and order.client_id == ^client_id and
            order.source == "app" and order.status != :cancelled and
            is_nil(order.deleted_at)

    query =
      if except_order_id, do: where(query, [order], order.id != ^except_order_id), else: query

    not Repo.exists?(query)
  end

  def eligible?(_branch_id, _client_id, _source, _except_order_id), do: false

  def existing_ids(nil), do: MapSet.new()

  def existing_ids(order_id) do
    from(r in Redemption, where: r.order_id == ^order_id, select: r.promotion_id)
    |> Repo.all()
    |> MapSet.new()
  end

  def condition?(nil), do: false
  def condition?(:first_order), do: true
  def condition?({:not, condition}), do: condition?(condition)

  def condition?({op, left, right}) when op in [:and, :or],
    do: condition?(left) or condition?(right)

  def condition?(_condition), do: false

  def required?(:first_order), do: true
  def required?({:and, left, right}), do: required?(left) or required?(right)
  def required?({:or, left, right}), do: required?(left) and required?(right)
  def required?(_condition), do: false
end
