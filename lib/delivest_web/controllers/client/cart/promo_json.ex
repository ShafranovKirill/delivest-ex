defmodule DelivestWeb.Client.Cart.PromoJSON do
  def code(nil), do: nil

  def code(state) do
    %{
      code: state.code,
      status: state.status,
      reason: state.reason,
      name: state.name,
      reasons: Enum.map(state.reasons, &reason/1)
    }
  end

  def applied(applied) do
    %{
      promotion_id: applied.promotion_id,
      name: applied.name,
      description: applied.description,
      code: applied.code,
      discount: applied.discount,
      gifts: applied.gifts
    }
  end

  def hint(hint) do
    %{
      promotion_id: hint.promotion_id,
      name: hint.name,
      description: hint.description,
      reasons: Enum.map(hint.reasons, &reason/1)
    }
  end

  def reason(%{type: :time, from: from, to: to}),
    do: %{type: :time, from: clock(from), to: clock(to)}

  def reason(reason), do: reason

  defp clock(%Time{} = time), do: Calendar.strftime(time, "%H:%M")
end
