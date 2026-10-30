defmodule Delivest.Integrations.AtolOnline do
  @behaviour Delivest.Fiscal.Provider

  alias Delivest.Integrations.AtolOnline.{Api, Payload}

  @auth_codes [12, 14, 20, 21]
  @permanent_codes [13, 32, 42]
  @retry_codes [1, 50]

  @impl true
  def key, do: :atol

  @impl true
  def name, do: "АТОЛ Онлайн"

  @impl true
  def body(receipt, built, settings) do
    now = DateTime.utc_now() |> Delivest.LocalTime.local(receipt.branch_id)

    url =
      DelivestWeb.Endpoint.url() <>
        "/integrations/fiscal/atol/" <> (settings.callback_token || "")

    Payload.build(built, receipt.id, url, now)
  end

  @impl true
  def register(receipt, body, settings) do
    body = Map.put(body, "external_id", external_id(receipt))

    case Api.register(settings, receipt.kind, body) do
      {:ok, response} -> {:ok, result(response)}
      {:error, {:atol, 33, _text}} -> {:ok, %{status: :wait}}
      error -> error
    end
  end

  @impl true
  def fetch(%{uuid: uuid}, settings) when is_binary(uuid) do
    case Api.report(settings, uuid) do
      {:ok, response} -> {:ok, result(response)}
      {:error, {:atol, 34, _text}} -> {:ok, %{status: :wait}}
      error -> error
    end
  end

  def fetch(receipt, _settings) do
    {:ok,
     %{
       status: :wait,
       error: "Проверьте чек в личном кабинете АТОЛ, external_id #{external_id(receipt)}"
     }}
  end

  @impl true
  def classify_error({:atol, code, _text}) when code in @auth_codes, do: :auth
  def classify_error({:atol, code, _text}) when code in @permanent_codes, do: :permanent
  def classify_error({:atol, code, _text}) when code in @retry_codes, do: :retry
  def classify_error({:atol, 56, _text}), do: {:snooze, 600}
  def classify_error({:atol, _code, _text}), do: :permanent
  def classify_error(_reason), do: :retry

  @impl true
  def callback_token(%{callback_token: token}), do: token
  def callback_token(_settings), do: nil

  @impl true
  def parse_callback(%{"uuid" => uuid} = params) when is_binary(uuid),
    do: {:ok, uuid, result(params)}

  def parse_callback(_params), do: {:error, :invalid_callback}

  @impl true
  def health_check(settings) do
    case Api.token(settings) do
      {:ok, _token, _ttl} -> :ok
      error -> error
    end
  end

  defp external_id(receipt), do: receipt.external_id || receipt.id

  defp result(response) do
    %{
      uuid: response["uuid"],
      external_id: response["external_id"],
      retriable: retriable?(response),
      status: status(response["status"]),
      payload: response["payload"],
      error: error_text(response["error"])
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp retriable?(%{"status" => "fail", "error" => %{"type" => "timeout"}}), do: true
  defp retriable?(_response), do: nil

  defp status("done"), do: :done
  defp status("fail"), do: :fail
  defp status(_status), do: :wait

  defp error_text(%{"text" => text, "code" => code}), do: "#{code}: #{text}"
  defp error_text(%{"text" => text}), do: text
  defp error_text(_error), do: nil
end
