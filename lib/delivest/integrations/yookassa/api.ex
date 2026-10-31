defmodule Delivest.Integrations.Yookassa.Api do
  alias Delivest.HTTP.Client
  alias Delivest.Integrations.Yookassa.Settings
  alias Delivest.Money

  @base_url "https://api.yookassa.ru/v3"

  def me(%Settings{} = settings), do: Client.get("/me", [], options(settings))

  def create_payment(%Settings{} = settings, key, attrs),
    do: Client.post("/payments", attrs, options(settings, key))

  def get_payment(%Settings{} = settings, id),
    do: Client.get("/payments/#{id}", [], options(settings))

  def capture(%Settings{} = settings, key, id, amount) do
    Client.post("/payments/#{id}/capture", %{amount: amount(amount)}, options(settings, key))
  end

  def cancel(%Settings{} = settings, key, id),
    do: Client.post("/payments/#{id}/cancel", %{}, options(settings, key))

  def create_refund(%Settings{} = settings, key, attrs),
    do: Client.post("/refunds", attrs, options(settings, key))

  def get_refund(%Settings{} = settings, id),
    do: Client.get("/refunds/#{id}", [], options(settings))

  def list_payments(%Settings{} = settings, params),
    do: Client.get("/payments", params, options(settings))

  def amount(kopecks) when is_integer(kopecks) do
    %{value: format(kopecks), currency: "RUB"}
  end

  def parse_amount(%{"value" => value}) when is_binary(value) do
    Money.parse(value)
  end

  def parse_amount(_amount), do: :error

  defp format(kopecks) do
    rubles = div(kopecks, 100)
    rest = kopecks |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{rubles}.#{rest}"
  end

  defp options(settings, idempotence_key \\ nil) do
    headers = [
      {"authorization", "Basic " <> Base.encode64("#{settings.shop_id}:#{settings.secret_key}")}
    ]

    headers =
      if idempotence_key, do: [{"idempotence-key", idempotence_key} | headers], else: headers

    [base_url: base_url(), headers: headers, journal: :yookassa]
  end

  defp base_url do
    case Application.get_env(:delivest, Delivest.Integrations.Yookassa, [])[:host] do
      host when is_binary(host) and host != "" -> host
      _default -> @base_url
    end
  end
end
