defmodule Delivest.Oms.Order.OrderNumber do
  alias Delivest.Repo

  def generate do
    case Repo.query("SELECT nextval('order_number_seq')") do
      {:ok, %Postgrex.Result{rows: [[seq_val]]}} ->
        {:ok, format_number(seq_val)}

      _ ->
        {:error, :failed_to_generate_number}
    end
  end

  defp format_number(seq_val) do
    letter_index = div(seq_val, 1000)
    number_part = rem(seq_val, 1000)

    letter = <<65 + letter_index::utf8>>

    num_str = String.pad_leading("#{number_part}", 3, "0")

    "#{letter}#{num_str}"
  end
end
