defmodule Delivest.Promo.Usage do
  import Ecto.Query, warn: false

  alias Delivest.Oms.Order
  alias Delivest.Promo.Redemption
  alias Delivest.Repo

  @type t :: %__MODULE__{
          total: %{binary() => non_neg_integer()},
          client: %{binary() => non_neg_integer()},
          code: %{binary() => non_neg_integer()}
        }

  defstruct total: %{}, client: %{}, code: %{}

  def load([], _client_id, _code_ids, _except_order_id), do: %__MODULE__{}

  def load(promotion_ids, client_id, code_ids, except_order_id) do
    base = counted(except_order_id)

    %__MODULE__{
      total: base |> where([r], r.promotion_id in ^promotion_ids) |> grouped(:promotion_id),
      client: client_counts(base, promotion_ids, client_id),
      code: code_counts(base, code_ids)
    }
  end

  def total(%__MODULE__{total: total}, promotion_id), do: Map.get(total, promotion_id, 0)
  def client(%__MODULE__{client: client}, promotion_id), do: Map.get(client, promotion_id, 0)
  def code(%__MODULE__{code: code}, code_id), do: Map.get(code, code_id, 0)

  defp counted(except_order_id) do
    query =
      from(r in Redemption,
        join: o in Order,
        on: o.id == r.order_id,
        where: is_nil(o.deleted_at) and o.status != :cancelled
      )

    if except_order_id, do: where(query, [r], r.order_id != ^except_order_id), else: query
  end

  defp client_counts(_base, _promotion_ids, nil), do: %{}

  defp client_counts(base, promotion_ids, client_id) do
    base
    |> where([r], r.promotion_id in ^promotion_ids and r.client_id == ^client_id)
    |> grouped(:promotion_id)
  end

  defp code_counts(_base, []), do: %{}

  defp code_counts(base, code_ids),
    do: base |> where([r], r.promo_code_id in ^code_ids) |> grouped(:promo_code_id)

  defp grouped(query, field) do
    query
    |> group_by([r], field(r, ^field))
    |> select([r], {field(r, ^field), count(r.id)})
    |> Repo.all()
    |> Map.new()
  end
end
