defmodule Delivest.Oms.Order.OrderNumber do
  alias Delivest.Identity.Branch
  alias Delivest.LocalTime

  @counter_sql """
  INSERT INTO order_counters (branch_id, business_date, value) VALUES ($1, $2, 1)
  ON CONFLICT (branch_id, business_date) DO UPDATE SET value = order_counters.value + 1
  RETURNING value
  """

  def next(repo, branch_id, now \\ DateTime.utc_now()) do
    date = LocalTime.business_date(now)

    with %Branch{code: code} when is_binary(code) <- repo.get(Branch, branch_id),
         {:ok, %{rows: [[value]]}} <- repo.query(@counter_sql, [dump(branch_id), date]) do
      {:ok, %{business_date: date, daily_number: value, number: full(date, code, value)}}
    else
      _ -> {:error, :failed_to_generate_number}
    end
  end

  def full(%Date{} = date, code, value),
    do: Calendar.strftime(date, "%y%m%d") <> "-" <> code <> "-" <> pad(value)

  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(3, "0")

  defp dump(branch_id), do: Ecto.UUID.dump!(branch_id)
end
