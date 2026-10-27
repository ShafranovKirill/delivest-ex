defmodule DelivestWeb.Plugs.YandexEdaJournal do
  import Plug.Conn

  require Logger

  @secret_params ["client_secret"]
  @max_length 4_000

  def init(opts), do: opts

  def call(conn, _opts) do
    started_at = System.monotonic_time(:millisecond)

    register_before_send(conn, fn conn ->
      Logger.info(fn -> entry(conn, System.monotonic_time(:millisecond) - started_at) end)
      conn
    end)
  end

  defp entry(conn, duration) do
    "yandex eda #{conn.method} #{conn.request_path} #{conn.status} in #{duration} ms" <>
      " request: #{conn.params |> Map.drop(@secret_params) |> encode()}" <>
      " response: #{(conn.resp_body || "") |> IO.iodata_to_binary() |> truncate()}"
  end

  defp encode(params), do: params |> Jason.encode!() |> truncate()

  defp truncate(text), do: String.slice(text, 0, @max_length)
end
