# Run with: STOREFRONT_MEASURE_MODE=legacy|bootstrap STOREFRONT_MEASURE_SLUG=demo-center mix run scripts/storefront_sql_measure.exs
# Use the same database and release settings for paired runs. Counts include Cachex Courier
# loader processes; unrelated background jobs should be idle during the short measurement.
alias Delivest.Repo
alias DelivestWeb.Endpoint

slug = System.get_env("STOREFRONT_MEASURE_SLUG", "demo-center")
mode = System.get_env("STOREFRONT_MEASURE_MODE", "bootstrap")
branch = Repo.get_by!(Delivest.Identity.Branch, slug: slug)

requests =
  case mode do
    "legacy" ->
      [
        {"franchise", :get, "/client/franchise"},
        {"branches", :get, "/client/branches"},
        {"select", :post, "/client/branches/slug/#{slug}/select"},
        {"menu", :get, "/client/branches/#{branch.id}/menu"},
        {"stocks", :get, "/client/#{branch.id}/stocks"},
        {"advertising", :get, "/client/branches/#{branch.id}/advertising/config"},
        {"cart", :get, "/client/cart?branch_id=#{branch.id}"},
        {"active_orders", :get, "/client/orders/active"},
        {"socket_token", :get, "/client/socket_token"}
      ]

    "bootstrap" ->
      [
        {"public_bootstrap", :get, "/client/storefront/v1/bootstrap?slug=#{slug}&locale=ru"},
        {"private_bootstrap", :get, "/client/session/bootstrap?branch_id=#{branch.id}"}
      ]

    other ->
      raise "Unknown STOREFRONT_MEASURE_MODE=#{inspect(other)}"
  end

handler = "storefront-sql-#{System.unique_integer([:positive])}"
owner = self()

:ok =
  :telemetry.attach(
    handler,
    [:delivest, :repo, :query],
    fn _, _, metadata, target ->
      query = metadata[:query] || ""

      unless String.contains?(query, "schema_migrations") or
               String.downcase(String.trim(query)) in ["begin", "commit", "rollback"] do
        send(target, {:storefront_sql, self(), query})
      end
    end,
    owner
  )

drain = fn ->
  Stream.repeatedly(fn ->
    receive do
      {:storefront_sql, pid, query} -> {:query, pid, query}
    after
      0 -> :done
    end
  end)
  |> Enum.take_while(&(&1 != :done))
end

IO.puts("pass,handler,status,sql_all_processes,sql_handler_process,elapsed_us,response_bytes")

Enum.reduce(1..3, nil, fn pass, prior ->
  Enum.reduce(requests, prior, fn {label, method, path}, previous ->
    drain.()
    conn = Plug.Test.conn(method, path) |> Plug.Conn.put_req_header("accept", "application/json")
    conn = if previous, do: Plug.Test.recycle_cookies(conn, previous), else: conn
    {micros, response} = :timer.tc(fn -> Endpoint.call(conn, Endpoint.init([])) end)
    queries = drain.()
    handler_count = Enum.count(queries, fn {:query, pid, _} -> pid == owner end)

    IO.puts(
      "#{pass},#{label},#{response.status},#{length(queries)},#{handler_count},#{micros},#{byte_size(response.resp_body || "")}"
    )

    response
  end)
end)

:telemetry.detach(handler)
