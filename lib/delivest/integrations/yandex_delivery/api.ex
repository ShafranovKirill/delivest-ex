defmodule Delivest.Integrations.YandexDelivery.Api do
  alias Delivest.HTTP.Client

  @base_url "https://b2b.taxi.yandex.net/b2b/cargo/integration/v2"

  def create(token, request_id, body),
    do: call(token, "/claims/create", [request_id: request_id], body)

  def info(token, claim_id), do: call(token, "/claims/info", [claim_id: claim_id], %{})

  def accept(token, claim_id, version),
    do: call(token, "/claims/accept", [claim_id: claim_id], %{version: version})

  def cancel_info(token, claim_id),
    do: call(token, "/claims/cancel-info", [claim_id: claim_id], %{})

  def cancel(token, claim_id, version, state),
    do:
      call(token, "/claims/cancel", [claim_id: claim_id], %{version: version, cancel_state: state})

  def journal(token, cursor),
    do: call(token, "/claims/journal", [], if(cursor, do: %{cursor: cursor}, else: %{}))

  def tracking_links(token, claim_id),
    do: fetch(token, "/claims/tracking-links", claim_id: claim_id)

  def courier_phone(token, claim_id, point_id),
    do: call(token, "/driver-voiceforwarding", [], %{claim_id: claim_id, point_id: point_id})

  defp call(token, path, query, body) do
    path
    |> with_query(query)
    |> Client.post(body, options(token))
    |> handle()
  end

  defp fetch(token, path, query) do
    path
    |> Client.get(query, options(token))
    |> handle()
  end

  defp options(token) do
    [
      base_url: base_url(),
      headers: [{"authorization", "Bearer " <> token}, {"accept-language", "ru"}]
    ]
  end

  defp handle(result) do
    case result do
      {:ok, %{} = response} ->
        {:ok, response}

      {:ok, body} ->
        {:error, {:yandex_delivery, :unexpected, body}}

      {:error, {:http_error, status, %{"code" => code}}} ->
        {:error, {:yandex_delivery, status, code}}

      {:error, {:http_error, status, _body}} ->
        {:error, {:yandex_delivery, status, nil}}

      error ->
        error
    end
  end

  defp with_query(path, []), do: path
  defp with_query(path, query), do: path <> "?" <> URI.encode_query(query)

  defp base_url,
    do: :delivest |> Application.get_env(__MODULE__, []) |> Keyword.get(:base_url, @base_url)
end
