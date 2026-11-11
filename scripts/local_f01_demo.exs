if Mix.env() != :dev do
  raise "Local F01 demo is only available in MIX_ENV=dev"
end

require Logger

database = System.get_env("DEV_DATABASE", "")
host = System.get_env("DEV_EXTERNAL_HOST", "")
port = System.get_env("PORT", "4000")

unless String.starts_with?(database, "delivest_f01_demo_") and host in ["127.0.0.1", "localhost"] and
         port == "4000" do
  raise "Refusing to start outside a dedicated local F01 demo database and port 4000"
end

defmodule LocalF01OfflinePlug do
  @moduledoc false

  def call(conn) do
    Plug.Conn.send_resp(conn, 503, "Local demo: external delivery disabled")
  end
end

for module <- [Delivest.HTTP.Client, Delivest.Push.Sender] do
  Application.put_env(:delivest, module,
    req_options: [plug: &LocalF01OfflinePlug.call/1, retry: false]
  )
end

Application.put_env(:delivest, Delivest.Integrations.Iiko, app_id: nil, client_secret: nil)
Application.put_env(:delivest, Delivest.Integrations.Rkeeper, token: nil)
Application.put_env(:delivest, Delivest.Integrations.AtolOnline, host: nil)
Application.put_env(:delivest, Delivest.Mailer, adapter: Swoosh.Adapters.Local)

oban = Application.fetch_env!(:delivest, Oban) |> Keyword.drop([:crontab, :pruner, :lifeline])

Application.put_env(
  :delivest,
  Oban,
  Keyword.merge(oban,
    queues: [default: 2, notifications: 2, events: 2, maintenance: 1, background: 1],
    plugins: [
      {Oban.Plugins.Cron, crontab: [{"*/5 * * * *", Delivest.Background.Dispatcher}]}
    ]
  )
)

Application.put_env(
  :delivest,
  DelivestWeb.Endpoint,
  Keyword.merge(Application.fetch_env!(:delivest, DelivestWeb.Endpoint), server: true)
)

Logger.configure(level: :info)
{:ok, _} = Application.ensure_all_started(:delivest)

{:ok, %{status: 503}} =
  Req.get("https://invalid.invalid/local-demo-offline-check",
    plug: &LocalF01OfflinePlug.call/1,
    retry: false
  )

try do
  Code.require_file("../priv/repo/local_f01_demo_seeds.exs", __DIR__)
rescue
  error -> Logger.error("F01 demo seed incomplete: #{Exception.message(error)}")
end

IO.puts("F01 demo backend: http://localhost:4000")
Process.sleep(:infinity)
