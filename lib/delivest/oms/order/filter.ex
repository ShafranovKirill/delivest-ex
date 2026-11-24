defmodule Delivest.Oms.Orders.Filter do
  import Ecto.Query, warn: false

  alias Delivest.Oms.{Order, OrderAttention, OrderScopes}
  alias Delivest.Oms.Orders.Search

  @statuses Enum.map(Order.statuses(), &to_string/1)

  def normalize_params(params) when is_map(params) do
    Map.new(params, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {to_string(k), v}
    end)
  end

  def apply_filters(query, params) do
    Enum.reduce(params, query, fn
      {_key, val}, q when val in [nil, ""] -> q
      {"branch_id", val}, q -> where(q, [o], o.branch_id == ^val)
      {"status", val}, q -> filter_status(q, val)
      {"receiving", val}, q -> filter_receiving(q, val)
      {"payment", val}, q -> filter_payment(q, val)
      {"source", val}, q -> filter_source(q, val)
      {"date_from", val}, q -> filter_date_from(q, val, zone(params))
      {"date_to", val}, q -> filter_date_to(q, val, zone(params))
      {"search", val}, q -> Search.apply(q, val)
      {"problem", val}, q when val in [true, "true", "on"] -> problem(q, params["branch_id"])
      {"sold", val}, q when val in [true, "true", "on"] -> OrderScopes.sold(q)
      {"hour", val}, q -> filter_hour(q, val, zone(params))
      {"sort_by", val}, q -> apply_sort(q, val, params["sort_dir"])
      _, q -> q
    end)
  end

  defp problem(q, branch_id) do
    where(q, ^OrderAttention.expression(branch_id))
  end

  defp filter_hour(q, hour, zone) when is_integer(hour) and hour in 0..23 do
    where(
      q,
      [o],
      fragment("extract(hour from timezone(?, timezone('UTC', ?)))::int", ^zone, o.inserted_at) ==
        ^hour
    )
  end

  defp filter_hour(q, hour, zone) when is_binary(hour) do
    case Integer.parse(hour) do
      {parsed, ""} -> filter_hour(q, parsed, zone)
      _ -> q
    end
  end

  defp filter_hour(q, _hour, _zone), do: q

  defp filter_status(q, status) when is_atom(status), do: filter_status(q, to_string(status))

  defp filter_status(q, status) when status in @statuses,
    do: where(q, [o], o.status == ^String.to_existing_atom(status))

  defp filter_status(q, _status), do: where(q, false)

  defp filter_receiving(q, val) when val in ~w(dine_in delivery pickup),
    do: where(q, [o], o.fulfillment_type == ^String.to_existing_atom(val))

  defp filter_receiving(q, _val), do: q

  defp filter_payment(q, val) when val in ~w(cash card_offline online),
    do: where(q, [o], o.payment_method == ^String.to_existing_atom(val))

  defp filter_payment(q, _val), do: q

  defp filter_source(q, val) when is_binary(val) do
    if Delivest.Oms.OrderSource.valid?(val), do: where(q, [o], o.source == ^val), else: q
  end

  defp filter_source(q, _val), do: q

  defp zone(params), do: Delivest.LocalTime.timezone(blank_to_nil(params["branch_id"]))

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp filter_date_from(q, %Date{} = date, zone) do
    where(q, [o], o.inserted_at >= ^Delivest.LocalTime.start_of_day_utc(date, zone))
  end

  defp filter_date_from(q, str, zone) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> filter_date_from(q, d, zone)
      _ -> q
    end
  end

  defp filter_date_to(q, %Date{} = date, zone) do
    where(q, [o], o.inserted_at <= ^Delivest.LocalTime.end_of_day_utc(date, zone))
  end

  defp filter_date_to(q, str, zone) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> filter_date_to(q, d, zone)
      _ -> q
    end
  end

  defp apply_sort(q, field, dir) do
    sort_field =
      case field do
        f when f in ["total_amount", "status"] -> String.to_existing_atom(f)
        _ -> :inserted_at
      end

    sort_dir = if dir in ["asc", :asc], do: :asc, else: :desc
    order_by(q, [o], [{^sort_dir, ^sort_field}])
  end
end
