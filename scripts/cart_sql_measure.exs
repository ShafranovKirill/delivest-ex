# Paired disposable DBs only:
# DEV_DATABASE=delivest_f01_demo_perf_before_20261119 mix run /absolute/path/cart_sql_measure.exs
# DEV_DATABASE=delivest_f01_demo_perf_after_20261119 mix run scripts/cart_sql_measure.exs
# Run each against the intended source checkout, with the same DEV_DATABASE_PORT/config.
alias Delivest.Repo
alias DelivestWeb.Endpoint

database = Repo.config()[:database]

unless database in [
         "delivest_f01_demo_perf_before_20261119",
         "delivest_f01_demo_perf_after_20261119"
       ] do
  raise "cart SQL measurement requires a disposable task database, got #{inspect(database)}"
end

branch = Repo.get_by!(Delivest.Identity.Branch, slug: "demo-center")
run_id = System.unique_integer([:positive])

request = fn method, path, params, previous ->
  body = if params, do: Jason.encode!(params), else: ""

  conn =
    Plug.Test.conn(method, path, body)
    |> Plug.Conn.put_req_header("accept", "application/json")
    |> Plug.Conn.put_req_header("content-type", "application/json")

  conn = if previous, do: Plug.Test.recycle_cookies(conn, previous), else: conn
  Endpoint.call(conn, Endpoint.init([]))
end

decode = fn conn -> Jason.decode!(conn.resp_body || "{}") end

new_cart = fn label ->
  session_id = Ecto.UUID.generate()
  path = "/client/cart?branch_id=#{branch.id}"

  conn =
    Plug.Test.conn(:get, path)
    |> Plug.Conn.put_req_header("accept", "application/json")
    |> Plug.Test.put_req_cookie("session_id", session_id)
    |> then(&Endpoint.call(&1, Endpoint.init([])))

  unless conn.status == 200, do: raise("#{label} cart setup failed: #{conn.status}")
  {conn, decode.(conn)["data"]["id"]}
end

menu = request.(:get, "/client/branches/#{branch.id}/menu", nil, nil) |> decode.()
products = Enum.flat_map(menu["data"], & &1["products"])
plain = Enum.find(products, &(is_nil(&1["modifier_groups"]) or &1["modifier_groups"] == [])) || hd(products)
with_modifiers = Enum.find(products, &(is_list(&1["modifier_groups"]) and &1["modifier_groups"] != []))

if is_nil(with_modifiers), do: raise("demo-center has no menu product with modifiers")

group = hd(with_modifiers["modifier_groups"])
choice = Enum.find(group["modifiers"], &(&1["is_active"] != false)) || hd(group["modifiers"])

promotion =
  Repo.insert!(%Delivest.Promo.Promotion{
    branch_id: branch.id,
    name: "Storefront SQL measure #{run_id}",
    kind: :public_code,
    rules: "then discount 10%",
    enabled: true
  })

code = "STF#{run_id}"

Repo.insert!(%Delivest.Promo.PromoCode{
  branch_id: branch.id,
  promotion_id: promotion.id,
  code: code
})

Delivest.Promo.Catalog.invalidate(branch.id)

handler = "cart-sql-measure-#{run_id}"
owner = self()

:ok =
  :telemetry.attach(
    handler,
    [:delivest, :repo, :query],
    fn _, _, metadata, pid ->
      query = metadata[:query] || ""
      normalized = query |> String.trim() |> String.downcase()

      unless String.contains?(query, "schema_migrations") do
        kind = if normalized in ["begin", "commit", "rollback"], do: :transaction, else: :data
        send(pid, {:measure_sql, self(), kind, metadata[:source] || "raw_sql"})
      end
    end,
    owner
  )

drain = fn ->
  Stream.repeatedly(fn ->
    receive do
      {:measure_sql, pid, kind, source} -> {pid, kind, source}
    after
      0 -> :done
    end
  end)
  |> Enum.take_while(&(&1 != :done))
end

measure = fn label, fun ->
  drain.()
  {micros, conn} = :timer.tc(fun)
  events = drain.()
  data = decode.(conn)["data"] || %{}

  summary = %{
    case: label,
    status: conn.status,
    sql_data_all_processes: Enum.count(events, &(elem(&1, 1) == :data)),
    sql_data_handler_process: Enum.count(events, fn {pid, kind, _} -> pid == owner and kind == :data end),
    sql_transaction_control: Enum.count(events, &(elem(&1, 1) == :transaction)),
    sql_sources:
      events
      |> Enum.filter(&(elem(&1, 1) == :data))
      |> Enum.frequencies_by(&elem(&1, 2)),
    elapsed_us: micros,
    response_bytes: byte_size(conn.resp_body || ""),
    item_count: if(is_list(data["items"]), do: length(data["items"]), else: nil),
    total_amount: data["total_amount"],
    discount_amount: data["discount_amount"],
    error: decode.(conn)["error"]
  }

  IO.puts(Jason.encode!(summary))
  conn
end

IO.puts(Jason.encode!(%{database: database, branch_slug: branch.slug, menu_products: length(products), modifier_choice: not is_nil(choice), mode: "cart_sql_measure_v1"}))

{plain_conn, plain_cart} = new_cart.("plain add")

plain_added =
  measure.("plain_add", fn ->
    request.(:post, "/client/cart/#{plain_cart}/items/#{plain["id"]}", %{quantity: 1}, plain_conn)
  end)

measure.("warm_nonempty_cart", fn ->
  request.(:get, "/client/cart?branch_id=#{branch.id}", nil, plain_added)
end)

{mod_conn, mod_cart} = new_cart.("modifier add")

mod_added =
  measure.("modifier_add", fn ->
    request.(:post, "/client/cart/#{mod_cart}/items/#{with_modifiers["id"]}", %{modifiers: [%{id: choice["id"]}]}, mod_conn)
  end)

key = mod_added |> decode.() |> get_in(["data", "items", Access.at(0), "key"])

measure.("modifier_replace", fn ->
  request.(:put, "/client/cart/#{mod_cart}/items/#{URI.encode(key)}", %{modifiers: [%{id: choice["id"]}]}, mod_added)
end)

{promo_conn, promo_cart} = new_cart.("valid promo")
promo_added = request.(:post, "/client/cart/#{promo_cart}/items/#{plain["id"]}", %{}, promo_conn)

measure.("valid_public_code", fn ->
  request.(:post, "/client/cart/#{promo_cart}/promo_code", %{code: code}, promo_added)
end)

{invalid_conn, invalid_cart} = new_cart.("invalid promo")
invalid_added = request.(:post, "/client/cart/#{invalid_cart}/items/#{plain["id"]}", %{}, invalid_conn)

measure.("invalid_code", fn ->
  request.(:post, "/client/cart/#{invalid_cart}/promo_code", %{code: "INVALID#{run_id}"}, invalid_added)
end)

{order_conn, order_cart} = new_cart.("checkout")
order_added = request.(:post, "/client/cart/#{order_cart}/items/#{plain["id"]}", %{}, order_conn)
expected_total = order_added |> decode.() |> get_in(["data", "total_amount"])

measure.("cash_pickup_checkout", fn ->
  request.(:post, "/client/orders", %{
    cart_id: order_cart,
    branch_id: branch.id,
    fulfillment_type: "pickup",
    payment_method: "cash",
    expected_total: expected_total
  }, order_added)
end)

:telemetry.detach(handler)
