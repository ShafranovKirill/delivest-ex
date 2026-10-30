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
      base_url: @base_url,
      journal: :zvonok
    )
    |> result()
  end

  @flash_path "/manager/cabapi_external/api/v1/phones/flashcall/"

  @spec flash(Settings.t(), String.t()) ::
          {:ok, %{call_id: String.t(), code: String.t()}} | {:error, term()}
  def flash(%Settings{} = config, phone) do
    @flash_path
    |> Client.post(
      [public_key: config.public_key, campaign_id: config.campaign_id, phone: phone],
      base_url: @base_url,
      format: :form,
      journal: :zvonok
    )
    |> flash_result()
  end

  defp flash_result({:ok, body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> flash_result({:ok, decoded})
      {:error, _reason} -> {:error, {:zvonok, body}}
    end
  end

  defp flash_result({:ok, %{"status" => "ok", "data" => %{"call_id" => call_id} = data} = body}) do
    case flash_code(data) || flash_code(body) do
      nil -> {:error, {:zvonok, :no_flash_code}}
      code -> {:ok, %{call_id: to_string(call_id), code: code}}
    end
  end

  defp flash_result({:ok, body}), do: {:error, {:zvonok, body}}
  defp flash_result(error), do: error

  defp flash_code(%{"pincode" => code}) when code not in [nil, ""], do: last_digits(code)
  defp flash_code(%{"code" => code}) when code not in [nil, ""], do: last_digits(code)

  defp flash_code(data) do
    Enum.find_value(
      ["flashcall_phone", "call_phone", "caller_id", "callerid", "phone_from", "from"],
      fn key -> if data[key] not in [nil, ""], do: last_digits(data[key]) end
    )
  end

  defp last_digits(value) do
    digits = value |> to_string() |> String.replace(~r/\D/, "")
    if String.length(digits) >= 4, do: String.slice(digits, -4, 4)
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
