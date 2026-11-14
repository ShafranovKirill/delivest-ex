if Mix.env() != :dev do
  raise "Local F01 demo is only available in MIX_ENV=dev"
end

require Logger

database = System.get_env("DEV_DATABASE", "")
host = System.get_env("DEV_EXTERNAL_HOST", "")
port = System.get_env("PORT", "4000")

unless String.starts_with?(database, "delivest_f01_demo_") and host in ["127.0.0.1", "localhost"] and
         (port == "4000" or
            (database == "delivest_f01_demo_local" and
               match?({value, ""} when value in 1024..65_535, Integer.parse(port)))) do
  raise "Refusing to start outside a dedicated local F01 demo database or allowed local port"
end

Application.put_env(
  :delivest,
  DelivestWeb.Endpoint,
  Keyword.merge(Application.fetch_env!(:delivest, DelivestWeb.Endpoint),
    server: System.get_env("LOCAL_DEMO_PREPARE") != "1"
  )
)

Logger.configure(level: :info)
{:ok, _} = Application.ensure_all_started(:delivest)

if System.get_env("LOCAL_DEMO_PREPARE") == "1" or database != "delivest_f01_demo_local" do
  try do
    Code.require_file("../priv/repo/local_f01_demo_seeds.exs", __DIR__)
  rescue
    error ->
      if System.get_env("LOCAL_DEMO_PREPARE") == "1", do: reraise(error, __STACKTRACE__)
      Logger.error("F01 demo seed incomplete: #{Exception.message(error)}")
  end
end

IO.puts("F01 demo backend: http://localhost:4000")
if System.get_env("LOCAL_DEMO_PREPARE") != "1", do: Process.sleep(:infinity)
