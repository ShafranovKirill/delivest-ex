defmodule Delivest.Oms.Order.OrderNumber do
  import Ecto.Query

  alias Delivest.Identity.Branch
  alias Delivest.LocalTime

  @counter_sql """
  INSERT INTO order_counters (branch_id, business_date, value) VALUES ($1, $2, 1)
  ON CONFLICT (branch_id, business_date) DO UPDATE SET value = order_counters.value + 1
  RETURNING value
  """

  def next(repo, branch_id, now \\ DateTime.utc_now()) do
    date = LocalTime.business_date(now)

    code =
      repo.one(from b in Branch, where: b.id == ^branch_id, select: b.code) || fallback(branch_id)

    case repo.query(@counter_sql, [dump(branch_id), date]) do
      {:ok, %{rows: [[value]]}} ->
        {:ok, %{business_date: date, daily_number: value, number: full(date, code, value)}}

      _ ->
        {:error, :failed_to_generate_number}
    end
  end

  def full(%Date{} = date, code, value),
    do: Calendar.strftime(date, "%y%m%d") <> "-" <> code <> "-" <> pad(value)

  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(3, "0")

  defp fallback(branch_id), do: branch_id |> String.slice(-6, 6) |> String.upcase()

  defp dump(branch_id), do: Ecto.UUID.dump!(branch_id)
end
