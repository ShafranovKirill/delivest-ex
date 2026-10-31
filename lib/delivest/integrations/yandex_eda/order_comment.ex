defmodule Delivest.Integrations.YandexEda.OrderComment do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Integrations.YandexEda.OrderRequest
  alias Delivest.Money

  @max_length 500

  def text(%OrderRequest{} = request) do
    [
      request.comment,
      change(request),
      pickup_code(request.pickup_code)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(". ")
    |> String.slice(0, @max_length)
  end

  defp change(%OrderRequest{paid: false, change: change}) when is_integer(change),
    do: gettext("Change from %{amount}", amount: Money.format(change))

  defp change(_request), do: nil

  defp pickup_code(code) when is_binary(code) and code != "",
    do: gettext("Courier code: %{code}", code: code)

  defp pickup_code(_code), do: nil
end
