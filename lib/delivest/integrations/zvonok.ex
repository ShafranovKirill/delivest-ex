defmodule Delivest.Integrations.Zvonok do
  alias Delivest.Integrations.Zvonok.{Api, Config}

  @spec request_call(String.t()) ::
          {:ok, %{call_id: String.t(), call_number: String.t()}} | {:error, term()}
  def request_call(phone) do
    with {:ok, config} <- Config.fetch() do
      Api.confirm(config, phone)
    end
  end

  @spec valid_webhook_token?(String.t()) :: boolean()
  def valid_webhook_token?(token) do
    case Config.fetch() do
      {:ok, config} -> Plug.Crypto.secure_compare(config.webhook_token, token)
      _ -> false
    end
  end
end
