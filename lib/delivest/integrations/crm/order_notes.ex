defmodule Delivest.Integrations.Crm.OrderNotes do
  use Gettext, backend: DelivestWeb.Gettext

  def text(order, max_length) do
    case order |> lines() |> Enum.join(". ") |> String.slice(0, max_length) do
      "" -> nil
      text -> text
    end
  end

  def lines(order) do
    [intercom(order.address), address_comment(order.address), order.comment]
    |> Enum.map(&trim/1)
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp intercom(%{intercom: code}) when is_binary(code) and code != "",
    do: gettext("Intercom %{code}", code: String.trim(code))

  defp intercom(_address), do: nil

  defp address_comment(%{comment: comment}), do: comment
  defp address_comment(_address), do: nil

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(_value), do: nil
end
