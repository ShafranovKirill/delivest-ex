defmodule Delivest.Promo.Selection do
  alias Delivest.Promo.Compiled

  @spec pick([Compiled.t()]) :: [Compiled.t()]
  def pick(candidates) do
    candidates
    |> Enum.reduce([], fn
      candidate, [] ->
        [candidate]

      candidate, selected ->
        if compatible?(candidate, selected), do: [candidate | selected], else: selected
    end)
    |> Enum.reverse()
  end

  defp compatible?(candidate, selected),
    do: combinable?(candidate) and Enum.all?(selected, &combinable?/1)

  defp combinable?(%Compiled{promotion: promotion}), do: promotion.combinable
end
