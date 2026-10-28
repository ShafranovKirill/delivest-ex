defmodule Delivest.Integrations.YandexEda.CourierCode do
  alias Delivest.{Identity, Repo}
  alias Delivest.Integrations.YandexEda.PushApi
  alias Delivest.Oms.Order

  @provider "yandex_eda"
  @no_attempts 1001

  def validate(settings, staff, branch_id, order_id, code) do
    with :ok <- Identity.authorize(staff, "orders.update", branch_id),
         {:ok, order} <- fetch(branch_id, order_id),
         {:ok, code} <- normalize(code) do
      settings
      |> PushApi.validate_code(order.id, code)
      |> result()
    end
  end

  defp fetch(branch_id, order_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(order_id),
         %Order{} = order <- Repo.get_by(Order, id: uuid, branch_id: branch_id, source: @provider) do
      {:ok, order}
    else
      _ -> {:error, :order_not_found}
    end
  end

  defp normalize(code) when is_binary(code) do
    case String.trim(code) do
      "" -> {:error, :empty_code}
      code -> {:ok, code}
    end
  end

  defp normalize(_code), do: {:error, :empty_code}

  defp result({:ok, %{"is_valid" => valid} = body}),
    do: {:ok, %{valid: valid == true, attempts_left: body["validation_attempts_left"]}}

  defp result({:error, {:http_error, 409, %{"code" => @no_attempts}}}), do: {:error, :no_attempts}
  defp result({:ok, body}), do: {:error, {:yandex_eda, body}}
  defp result(error), do: error
end
