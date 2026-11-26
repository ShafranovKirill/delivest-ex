# Safe cold run (an isolated local perf database only):
# DEV_DATABASE=delivest_demo_perf_20261126 STOREFRONT_MEASURE_ACK=clear-isolated-caches \
# STOREFRONT_MEASURE_OUTPUT=/tmp/storefront-sql.json mix run --no-start scripts/storefront_sql_measure.exs
# STOREFRONT_MEASURE_MODE=legacy|bootstrap preserves the previous paired-path measurement.
# Cold clears every application Cachex cache, but keeps the DB and revision ETS process live.
# Keep unrelated traffic idle: Repo telemetry also sees concurrent background queries.
mode = System.get_env("STOREFRONT_MEASURE_MODE", "cold")

if mode == "cold" do
  unless Mix.env() == :dev and
           System.get_env("STOREFRONT_MEASURE_ACK") == "clear-isolated-caches" do
    raise "cold measurement requires MIX_ENV=dev and STOREFRONT_MEASURE_ACK=clear-isolated-caches"
  end

  repo_config = Application.fetch_env!(:delivest, Delivest.Repo)
  database = Keyword.fetch!(repo_config, :database)
  hostname = Keyword.fetch!(repo_config, :hostname)

  unless is_binary(database) and
           Regex.match?(~r/(?:^|_)(?:perf|benchmark|test)(?:_|$)/, database) and
           hostname in ["localhost", "127.0.0.1", "::1"] do
    raise "cold measurement requires an isolated perf/test database on localhost"
  end

  # mix run --no-start is required: disable listeners and background Oban jobs before boot.
  if Application.started_applications() |> Enum.any?(fn {name, _, _} -> name == :delivest end) do
    raise "start with mix run --no-start so application startup is controlled"
  end

  alias Delivest.Repo
  alias Delivest.Storefront.Revisions
  alias DelivestWeb.Endpoint

  Application.put_env(
    :delivest,
    Endpoint,
    Keyword.merge(Application.fetch_env!(:delivest, Endpoint),
      server: false,
      reloadable_apps: [],
      code_reloader: false,
      watchers: []
    )
  )

  Application.put_env(
    :delivest,
    Oban,
    Keyword.merge(Application.fetch_env!(:delivest, Oban),
      queues: [],
      plugins: false,
      peer: false
    )
  )

  {:ok, _} = Application.ensure_all_started(:delivest)

  slug = System.get_env("STOREFRONT_MEASURE_SLUG", "demo-center")
  branch = Repo.get_by!(Delivest.Identity.Branch, slug: slug)
  route = "/" <> URI.encode(slug)
  section = "/client/storefront/v1/sections/menu?branch_id=#{branch.id}&locale=ru"

  endpoints = [
    {"seo-head", "/seo/head", [{"x-original-uri", route}]},
    {"seo-content", "/seo/content", [{"x-original-uri", route}]},
    {"public-bootstrap", "/client/storefront/v1/bootstrap?slug=#{URI.encode(slug)}&locale=ru",
     []},
    {"private-bootstrap", "/client/session/bootstrap?branch_id=#{branch.id}", []},
    {"section-200", section, []},
    {"section-conditional", section, []}
  ]

  cache_names = [
    :staff_cache,
    :branch_cache,
    :menu_cache,
    :stock_cache,
    :cart_cache,
    :promo_cache,
    :franchise_cache,
    :rate_limit_cache,
    :geo_cache,
    :crm_cache,
    :token_cache,
    :stop_cache,
    :storefront_cache
  ]

  owner = self()
  handler = "storefront-sql-#{System.unique_integer([:positive])}"

  :ok =
    :telemetry.attach(
      handler,
      [:delivest, :repo, :query],
      fn _, measurements, metadata, target ->
        query = metadata[:query] || ""

        verb =
          query
          |> String.trim()
          |> String.split(~r/\s+/, parts: 2)
          |> List.first()
          |> String.upcase()

        unless String.contains?(query, "schema_migrations") or
                 verb in ["BEGIN", "COMMIT", "ROLLBACK"] do
          tables =
            Regex.scan(~r/\b(?:FROM|JOIN|UPDATE|INTO)\s+"?([a-z][a-z_0-9]*)/i, query,
              capture: :all_but_first
            )
            |> List.flatten()
            |> Enum.uniq()

          to_us = fn key ->
            System.convert_time_unit(Map.get(measurements, key, 0), :native, :microsecond)
          end

          send(
            target,
            {:storefront_sql,
             %{
               caller: self() == target,
               verb: verb,
               tables: tables,
               query_us: to_us.(:query_time),
               queue_us: to_us.(:queue_time)
             }}
          )
        end
      end,
      owner
    )

  drain = fn ->
    Stream.repeatedly(fn ->
      receive do
        {:storefront_sql, query} -> query
      after
        0 -> nil
      end
    end)
    |> Enum.take_while(& &1)
  end

  IO.puts(
    "run,phase,endpoint,status,sql_all_processes,query_us,queue_us,elapsed_us,response_bytes"
  )

  try do
    rows =
      for run <- 1..3, reduce: [] do
        accumulated ->
          Enum.each(cache_names, fn name ->
            case Cachex.clear(name) do
              {:ok, _} -> :ok
              error -> raise "Cachex.clear(#{inspect(name)}) failed: #{inspect(error)}"
            end
          end)

          :ok = Revisions.sync()
          drain.()

          {run_rows, _} =
            Enum.map_reduce(["cold-application", "warm-application"], nil, fn phase, previous ->
              {phase_rows, {previous, _tag}} =
                Enum.map_reduce(endpoints, {previous, nil}, fn {label, path, headers},
                                                               {prior, tag} ->
                  conn =
                    Plug.Test.conn(:get, path)
                    |> Plug.Conn.put_req_header("accept", "application/json")

                  conn = if prior, do: Plug.Test.recycle_cookies(conn, prior), else: conn

                  headers =
                    if label == "section-conditional",
                      do: [{"if-none-match", tag} | headers],
                      else: headers

                  conn =
                    Enum.reduce(headers, conn, fn {key, value}, c ->
                      Plug.Conn.put_req_header(c, key, value)
                    end)

                  drain.()

                  {elapsed_us, response} =
                    :timer.tc(fn -> Endpoint.call(conn, Endpoint.init([])) end)

                  sql = drain.()

                  expected =
                    case label do
                      "seo-content" -> [200, 204]
                      "section-conditional" -> [304]
                      _ -> [200]
                    end

                  unless response.status in expected,
                    do: raise("#{label} returned #{response.status}")

                  if label == "section-conditional" and response.resp_body != "",
                    do: raise("304 returned body")

                  if label == "private-bootstrap" and
                       Plug.Conn.get_resp_header(response, "cache-control") != [
                         "private, no-store"
                       ], do: raise("private cache-control changed")

                  tag =
                    if label == "section-200" do
                      [new_tag] = Plug.Conn.get_resp_header(response, "etag")
                      new_tag
                    else
                      tag
                    end

                  groups =
                    Enum.reduce(sql, %{}, fn query, groups ->
                      # Queries touching several tables contribute to each table's group.
                      Enum.reduce(query.tables, groups, fn table, totals ->
                        Map.update(
                          totals,
                          table,
                          %{count: 1, query_us: query.query_us, queue_us: query.queue_us},
                          fn value ->
                            %{
                              count: value.count + 1,
                              query_us: value.query_us + query.query_us,
                              queue_us: value.queue_us + query.queue_us
                            }
                          end
                        )
                      end)
                    end)

                  row = %{
                    run: run,
                    phase: phase,
                    endpoint: label,
                    status: response.status,
                    bytes: byte_size(response.resp_body || ""),
                    elapsed_us: elapsed_us,
                    sql_count: length(sql),
                    query_us: Enum.sum(Enum.map(sql, & &1.query_us)),
                    queue_us: Enum.sum(Enum.map(sql, & &1.queue_us)),
                    table_groups: groups,
                    sql: sql
                  }

                  IO.puts(
                    Enum.join(
                      [
                        run,
                        phase,
                        label,
                        row.status,
                        row.sql_count,
                        row.query_us,
                        row.queue_us,
                        elapsed_us,
                        row.bytes
                      ],
                      ","
                    )
                  )

                  {row, {response, tag}}
                end)

              {phase_rows, previous}
            end)

          accumulated ++ List.flatten(run_rows)
      end

    case System.get_env("STOREFRONT_MEASURE_OUTPUT") do
      nil -> IO.puts(:stderr, "Set STOREFRONT_MEASURE_OUTPUT to save raw JSON samples")
      path -> File.write!(path, Jason.encode!(rows, pretty: true))
    end
  after
    :telemetry.detach(handler)
  end
else
  unless mode in ["legacy", "bootstrap"],
    do: raise("unknown STOREFRONT_MEASURE_MODE=#{inspect(mode)}")

  # Preserve the historical baseline measurement paths and output columns.
  # Its original implementation follows below, selected only by the explicit old mode.
  Code.eval_file(Path.join(__DIR__, "storefront_sql_measure_legacy.exs"))
end
