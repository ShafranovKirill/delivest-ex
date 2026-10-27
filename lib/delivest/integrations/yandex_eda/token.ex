defmodule Delivest.Integrations.YandexEda.Token do
  alias Delivest.Integrations.YandexEda.Settings

  @salt "yandex_eda"
  @max_age 24 * 3600

  def issue(%Settings{} = settings),
    do: Phoenix.Token.sign(DelivestWeb.Endpoint, @salt, fingerprint(settings))

  def valid?(%Settings{} = settings, token) when is_binary(token) do
    case Phoenix.Token.verify(DelivestWeb.Endpoint, @salt, token, max_age: @max_age) do
      {:ok, fingerprint} -> Plug.Crypto.secure_compare(fingerprint, fingerprint(settings))
      {:error, _reason} -> false
    end
  end

  def valid?(_settings, _token), do: false

  def max_age, do: @max_age

  defp fingerprint(settings),
    do:
      :crypto.hash(:sha256, settings.client_id <> ":" <> settings.client_secret)
      |> Base.encode16()
end
