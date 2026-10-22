defmodule Delivest.Integrations.Zvonok.Api do
  alias Delivest.HTTP.Client
  alias Delivest.Integrations.Zvonok.Settings

  @base_url "https://zvonok.com"
  @confirm_path "/manager/cabapi_external/api/v1/phones/confirm/"

  @spec confirm(Settings.t(), String.t()) ::
          {:ok, %{call_id: String.t(), call_number: String.t()}} | {:error, term()}
  def confirm(%Settings{} = config, phone) do
    @confirm_path
    |> Client.get(
      [public_key: config.public_key, campaign_id: config.campaign_id, phone: phone],
      base_url: @base_url
    )
    |> result()
  end

  defp result({:ok, %{"status" => "ok", "data" => %{"call_id" => call_id} = data} = body}) do
    case call_number(data["allowed_phones_for_call"] || body["allowed_phones_for_call"]) do
      nil -> {:error, {:zvonok, :no_call_number}}
      number -> {:ok, %{call_id: to_string(call_id), call_number: number}}
    end
  end

  defp result({:ok, body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> result({:ok, decoded})
      {:error, _reason} -> {:error, {:zvonok, body}}
    end
  end

  defp result({:ok, body}), do: {:error, {:zvonok, body}}
  defp result(error), do: error

  defp call_number([number | _]), do: call_number(number)
  defp call_number(number) when is_binary(number) and number != "", do: number
  defp call_number(number) when is_integer(number), do: Integer.to_string(number)
  defp call_number(_number), do: nil
end
