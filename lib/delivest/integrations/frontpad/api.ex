defmodule Delivest.Integrations.Frontpad.Api do
  alias Delivest.HTTP.Client

  @base_url "https://app.frontpad.ru"

  def new_order(form_params) do
    "/api/index.php?new_order"
    |> Client.post(form_params, base_url: @base_url, format: :form, decode_json: true)
    |> decode()
    |> result()
  end

  defp decode({:ok, body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, {:invalid_json, body, reason}}
    end
  end

  defp decode(response), do: response

  defp result({:ok, %{"result" => "success", "order_id" => order_id}}),
    do: {:ok, to_string(order_id)}

  defp result({:ok, %{"result" => "error", "error" => error}}),
    do: {:error, {:frontpad_api_error, error}}

  defp result({:ok, other}), do: {:error, {:unexpected_response, other}}
  defp result(error), do: error
end
