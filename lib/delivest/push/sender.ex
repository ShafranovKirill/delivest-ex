defmodule Delivest.Push.Sender do
  alias Delivest.Push.{Encryption, Vapid}

  @ttl_seconds 3600

  def deliver(%{endpoint: _, p256dh: _, auth: _} = subscription, payload) do
    body =
      payload |> Jason.encode!() |> Encryption.encrypt(subscription.p256dh, subscription.auth)

    [
      method: :post,
      url: subscription.endpoint,
      body: body,
      headers: [
        {"authorization", Vapid.authorization(subscription.endpoint)},
        {"content-encoding", "aes128gcm"},
        {"content-type", "application/octet-stream"},
        {"ttl", Integer.to_string(@ttl_seconds)},
        {"urgency", "high"}
      ]
    ]
    |> Keyword.merge(config_options())
    |> Req.request()
    |> result()
  end

  defp result({:ok, %{status: status}}) when status in 200..299, do: :ok
  defp result({:ok, %{status: status}}) when status in [404, 410], do: :expired
  defp result({:ok, %{status: status}}), do: {:error, {:http_error, status}}
  defp result({:error, exception}), do: {:error, exception}

  defp config_options,
    do: :delivest |> Application.get_env(__MODULE__, []) |> Keyword.get(:req_options, [])
end
