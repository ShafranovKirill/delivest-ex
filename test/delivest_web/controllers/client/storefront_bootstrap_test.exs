defmodule DelivestWeb.Client.StorefrontBootstrapTest do
  use DelivestWeb.ConnCase, async: false

  import Delivest.Factory

  alias Delivest.Oms.Carts
  alias Delivest.Repo

  setup do
    Cachex.clear(:storefront_cache)

    :ok
  end

  test "public bootstrap includes selected branch and no session cookie", %{conn: conn} do
    branch = insert(:branch, is_active: true)

    Repo.insert!(%Delivest.Identity.Branch.BranchInfo{
      branch_id: branch.id,
      phone_number: "+74951234567"
    })

    refresh_revisions()
    response = get(conn, "/client/storefront/v1/bootstrap?slug=#{branch.slug}&locale=ru")
    data = json_response(response, 200)

    assert data["schema_version"] == 1
    assert data["locale"] == "ru"
    assert data["selected_branch"]["id"] == branch.id
    assert is_list(data["branches"])

    assert Enum.find(data["branches"], &(&1["id"] == branch.id))["branch_info"]["phone_number"] ==
             "+74951234567"

    assert is_list(data["menu"])
    assert is_list(data["stories"])
    assert is_map(data["advertising"])
    refute get_resp_header(response, "set-cookie") != []
    assert get_resp_header(response, "cache-control") == ["no-store"]
  end

  test "warm bootstrap publishes cutlery setting after revision change", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    refresh_revisions()

    path = "/client/storefront/v1/bootstrap?slug=#{branch.slug}&locale=ru"
    first = conn |> get(path) |> json_response(200)
    assert first["franchise"]["cutlery_enabled"] == false

    {:ok, _settings} = Delivest.Franchise.SettingsStore.save(%{cutlery_enabled: true})
    refresh_revisions()
    second = conn |> recycle() |> get(path) |> json_response(200)
    assert second["franchise"]["cutlery_enabled"] == true
    assert second["revisions"]["franchise"] != first["revisions"]["franchise"]

    handler = "cutlery-bootstrap-warm-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:delivest, :repo, :query],
      fn _, _, metadata, owner ->
        if self() == owner and not String.contains?(metadata[:query] || "", "schema_migrations") do
          send(owner, :sql_query)
        end
      end,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    assert conn |> recycle() |> get(path) |> json_response(200)
    refute_received :sql_query
  end

  test "maintenance changes effective branch state and both public revisions", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    other_branch = insert(:branch, is_active: true)
    info = Repo.insert!(%Delivest.Identity.Branch.BranchInfo{branch_id: branch.id})
    Repo.insert!(%Delivest.Identity.Branch.BranchInfo{branch_id: other_branch.id})
    refresh_revisions()

    initial =
      conn
      |> get("/client/storefront/v1/bootstrap?slug=#{branch.slug}&locale=ru")
      |> json_response(200)

    assert initial["franchise"]["maintenance_enabled"] == false

    assert initial["selected_branch"]["branch_info"]["maintenance"] ==
             %{"enabled" => false, "reason" => nil}

    info |> Ecto.Changeset.change(maintenance_enabled: true) |> Repo.update!()
    refresh_revisions()

    by_branch =
      conn
      |> recycle()
      |> get("/client/storefront/v1/bootstrap?slug=#{branch.slug}&locale=ru")
      |> json_response(200)

    assert by_branch["selected_branch"]["branch_info"]["maintenance"] ==
             %{"enabled" => true, "reason" => "branch"}

    assert Enum.find(by_branch["branches"], &(&1["id"] == other_branch.id))["branch_info"][
             "maintenance"
           ] ==
             %{"enabled" => false, "reason" => nil}

    assert by_branch["revisions"]["branches"] != initial["revisions"]["branches"]

    stale_settings = Delivest.Franchise.SettingsStore.get()
    {:ok, _} = Delivest.Franchise.SettingsStore.save(%{maintenance_enabled: true})
    refresh_revisions()
    Cachex.put(:franchise_cache, :settings, stale_settings)

    by_franchise =
      conn
      |> recycle()
      |> get("/client/storefront/v1/bootstrap?slug=#{branch.slug}&locale=ru")
      |> json_response(200)

    assert by_franchise["franchise"]["maintenance_enabled"] == true

    assert by_franchise["selected_branch"]["branch_info"]["maintenance"] ==
             %{"enabled" => true, "reason" => "franchise"}

    assert Enum.find(by_franchise["branches"], &(&1["id"] == other_branch.id))["branch_info"][
             "maintenance"
           ] ==
             %{"enabled" => true, "reason" => "franchise"}

    assert by_franchise["revisions"]["franchise"] != by_branch["revisions"]["franchise"]
    assert by_franchise["revisions"]["branches"] != by_branch["revisions"]["branches"]

    {:ok, _} = Delivest.Franchise.SettingsStore.save(%{maintenance_enabled: false})
    refresh_revisions()

    restored =
      conn
      |> recycle()
      |> get("/client/storefront/v1/bootstrap?slug=#{branch.slug}&locale=ru")
      |> json_response(200)

    assert restored["selected_branch"]["branch_info"]["maintenance"] ==
             %{"enabled" => true, "reason" => "branch"}

    assert Enum.find(restored["branches"], &(&1["id"] == other_branch.id))["branch_info"][
             "maintenance"
           ] ==
             %{"enabled" => false, "reason" => nil}
  end

  test "unknown slug is not substituted with another branch", %{conn: conn} do
    insert(:branch, is_active: true)
    refresh_revisions()
    response = get(conn, "/client/storefront/v1/bootstrap?slug=missing")
    assert json_response(response, 404)["error"] == "branch_not_found"
  end

  test "root bootstrap without a choice returns branch list for selection", %{conn: conn} do
    insert(:branch, is_active: true)
    insert(:branch, is_active: true)
    refresh_revisions()

    data = conn |> get("/client/storefront/v1/bootstrap?locale=ru") |> json_response(200)
    assert data["selected_branch"] == nil
    assert length(data["branches"]) == 2
    assert data["menu"] == nil
  end

  test "manifest rejects a branch after deactivation even with a warmed branch list", %{
    conn: conn
  } do
    branch = insert(:branch, is_active: true)
    refresh_revisions()
    path = "/client/storefront/v1/manifest?branch_id=#{branch.id}"
    assert conn |> get(path) |> json_response(200)

    branch |> Ecto.Changeset.change(is_active: false) |> Repo.update!()
    refresh_worker()

    assert conn |> recycle() |> get(path) |> json_response(404)
  end

  test "private bootstrap does not create a new guest cart and gives one socket token", %{
    conn: conn
  } do
    branch = insert(:branch, is_active: true)
    response = get(conn, "/client/session/bootstrap?branch_id=#{branch.id}")
    data = json_response(response, 200)

    assert data["cart"] == nil
    assert data["active_orders"] == []
    assert is_binary(data["socket_token"])
    assert get_resp_header(response, "cache-control") == ["private, no-store"]
    assert Repo.aggregate(Delivest.Oms.Cart, :count) == 0
  end

  test "private bootstrap restores an existing guest cart", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    session_id = Ecto.UUID.generate()
    {:ok, cart} = Carts.get_or_create_cart(session_id: session_id, branch_id: branch.id)

    response =
      conn
      |> Plug.Test.put_req_cookie("session_id", session_id)
      |> get("/client/session/bootstrap?branch_id=#{branch.id}")

    assert json_response(response, 200)["cart"]["id"] == cart.id
  end

  test "private bootstrap scopes cart lookup to the actual session and branch", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    other_branch = insert(:branch, is_active: true)
    owner_session = Ecto.UUID.generate()
    {:ok, cart} = Carts.get_or_create_cart(session_id: owner_session, branch_id: branch.id)

    stranger =
      conn
      |> Plug.Test.put_req_cookie("session_id", Ecto.UUID.generate())
      |> get("/client/session/bootstrap?branch_id=#{branch.id}")

    assert json_response(stranger, 200)["cart"] == nil

    wrong_branch =
      conn
      |> Plug.Test.put_req_cookie("session_id", owner_session)
      |> get("/client/session/bootstrap?branch_id=#{other_branch.id}")

    assert json_response(wrong_branch, 200)["cart"] == nil

    owner =
      conn
      |> Plug.Test.put_req_cookie("session_id", owner_session)
      |> get("/client/session/bootstrap?branch_id=#{branch.id}")

    assert json_response(owner, 200)["cart"]["id"] == cart.id
  end

  test "same session guest login and logout rebinds cart pricing identity", %{conn: conn} do
    insert(:zvonok_settings)
    branch = insert(:branch, is_active: true)
    client = insert(:client)
    session_id = Ecto.UUID.generate()
    {:ok, cart} = Carts.get_or_create_cart(session_id: session_id, branch_id: branch.id)
    path = "/client/session/bootstrap?branch_id=#{branch.id}"
    %{access_token: access} = DelivestWeb.ClientToken.issue(client.id)

    signed_in =
      conn
      |> Plug.Test.put_req_cookie("session_id", session_id)
      |> Plug.Conn.put_req_header("authorization", "Bearer " <> access)
      |> get(path)

    assert json_response(signed_in, 200)["cart"]["id"] == cart.id
    assert Repo.get!(Delivest.Oms.Cart, cart.id).client_id == client.id

    signed_out =
      conn
      |> Plug.Test.put_req_cookie("session_id", session_id)
      |> get(path)

    assert json_response(signed_out, 200)["cart"]["id"] == cart.id
    assert Repo.get!(Delivest.Oms.Cart, cart.id).client_id == nil
  end

  test "warm public bootstrap performs no application SQL", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    refresh_revisions()
    path = "/client/storefront/v1/bootstrap?slug=#{branch.slug}&locale=ru"
    assert conn |> get(path) |> json_response(200)

    handler = "storefront-warm-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:delivest, :repo, :query],
      fn _, _, metadata, owner ->
        if self() == owner and not String.contains?(metadata[:query] || "", "schema_migrations") do
          send(owner, :sql_query)
        end
      end,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    assert conn |> recycle() |> get(path) |> json_response(200)
    refute_received :sql_query
  end

  test "a branch stop changes only its menu revision and rollback leaves revisions intact" do
    first = insert(:branch, is_active: true)
    second = insert(:branch, is_active: true)
    product = insert(:product)
    before_first = revision("menu", first.id)
    before_second = revision("menu", second.id)

    stop = %Delivest.Net.ProductStop{
      branch_id: first.id,
      product_id: product.id,
      source: "manual"
    }

    assert {:error, :rolled_back} =
             Repo.transaction(fn ->
               Repo.insert!(stop)
               Repo.rollback(:rolled_back)
             end)

    assert revision("menu", first.id) == before_first

    Repo.insert!(stop)
    assert revision("menu", first.id) == before_first + 1
    assert revision("menu", second.id) == before_second
  end

  test "committed branch slug refresh removes the old public route", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    refresh_revisions()

    assert conn
           |> get("/client/storefront/v1/bootstrap?slug=#{branch.slug}")
           |> json_response(200)

    new_slug = "updated-#{System.unique_integer([:positive])}"
    branch |> Ecto.Changeset.change(slug: new_slug) |> Repo.update!()
    refresh_worker()

    assert conn
           |> recycle()
           |> get("/client/storefront/v1/bootstrap?slug=#{branch.slug}")
           |> json_response(404)

    assert conn
           |> recycle()
           |> get("/client/storefront/v1/bootstrap?slug=#{new_slug}")
           |> json_response(200)
  end

  test "scoped stop refresh preserves another branch menu cache" do
    first = insert(:branch, is_active: true)
    second = insert(:branch, is_active: true)
    product = insert(:product)
    refresh_worker()

    Cachex.put(:storefront_cache, {:menu, first.id, "ru", "old"}, :first)
    Cachex.put(:storefront_cache, {:menu, second.id, "ru", "old"}, :second)

    Repo.insert!(%Delivest.Net.ProductStop{
      branch_id: first.id,
      product_id: product.id,
      source: "manual"
    })

    refresh_worker()

    assert Cachex.get(:storefront_cache, {:menu, first.id, "ru", "old"}) == {:ok, nil}
    assert Cachex.get(:storefront_cache, {:menu, second.id, "ru", "old"}) == {:ok, :second}
  end

  test "product edit is visible even if legacy catalog cache holds the old value", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    category = insert(:category)
    product = insert(:product, category_id: category.id)
    Delivest.Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id)
    Delivest.Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)
    refresh_revisions()
    {:ok, _} = Delivest.Net.Catalogs.get_menu_for_branch(branch.id)

    path = "/client/storefront/v1/bootstrap?slug=#{branch.slug}"
    first = conn |> get(path) |> json_response(200)
    old_price = first["menu"] |> hd() |> Map.fetch!("products") |> hd() |> Map.fetch!("price")

    product |> Ecto.Changeset.change(price: 20_000) |> Repo.update!()
    refresh_worker()
    second = conn |> recycle() |> get(path) |> json_response(200)
    new_price = second["menu"] |> hd() |> Map.fetch!("products") |> hd() |> Map.fetch!("price")
    refute new_price == old_price
  end

  test "franchise timezone and loyalty changes invalidate branch projection", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    Repo.insert!(%Delivest.Identity.Branch.BranchInfo{branch_id: branch.id})
    refresh_revisions()
    path = "/client/storefront/v1/bootstrap?slug=#{branch.slug}"
    first = conn |> get(path) |> json_response(200)
    assert first["selected_branch"]["branch_info"]["timezone"] == "Europe/Moscow"
    before_revision = revision("branches", "*")

    settings = Delivest.Franchise.SettingsStore.get_uncached()
    settings |> Ecto.Changeset.change(timezone: "Asia/Omsk") |> Repo.insert_or_update!()
    assert revision("branches", "*") == before_revision + 1
    refresh_worker()

    second = conn |> recycle() |> get(path) |> json_response(200)
    assert second["selected_branch"]["branch_info"]["timezone"] == "Asia/Omsk"
  end

  test "redemption and sold status changes invalidate only the affected menu" do
    branch = insert(:branch, is_active: true)
    other = insert(:branch, is_active: true)
    promotion = insert(:promotion, branch_id: branch.id, usage_limit: 1)
    {:ok, cart} = Carts.get_or_create_cart(session_id: "revision-test", branch_id: branch.id)

    order =
      Repo.insert!(%Delivest.Oms.Order{
        branch_id: branch.id,
        cart_id: cart.id,
        business_date: Date.utc_today(),
        daily_number: 1,
        session_id: "revision-test",
        number: "revision-test"
      })

    before_branch = revision("menu", branch.id)
    before_other = revision("menu", other.id)

    redemption =
      Repo.insert!(%Delivest.Promo.Redemption{
        order_id: order.id,
        promotion_id: promotion.id,
        discount: 100
      })

    assert revision("menu", branch.id) == before_branch + 1
    assert revision("menu", other.id) == before_other

    order |> Ecto.Changeset.change(status: :cancelled) |> Repo.update!()
    assert revision("menu", branch.id) == before_branch + 2

    Repo.delete!(redemption)
    assert revision("menu", branch.id) == before_branch + 3
    assert revision("menu", other.id) == before_other
  end

  test "bootstrap retries when franchise revision changes after franchise data was loaded", %{
    conn: conn
  } do
    branch = insert(:branch, is_active: true)
    refresh_revisions()
    path = "/client/storefront/v1/bootstrap?slug=#{branch.slug}"
    owner = self()
    gate = :atomics.new(1, [])
    handler = "storefront-interleave-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:delivest, :repo, :query],
        fn _, _, metadata, _ ->
          if String.contains?(metadata[:query] || "", "product_stops") and
               :atomics.compare_exchange(gate, 1, 0, 1) == :ok do
            send(owner, {:menu_loading, self()})

            receive do
              :continue -> :ok
            after
              5_000 -> :ok
            end
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    task = Task.async(fn -> conn |> get(path) |> json_response(200) end)
    assert_receive {:menu_loading, loader}, 5_000

    settings = Delivest.Franchise.SettingsStore.get_uncached()
    settings |> Ecto.Changeset.change(name: "Fresh franchise") |> Repo.insert_or_update!()
    refresh_worker()
    send(loader, :continue)

    result = Task.await(task, 10_000)
    assert result["franchise"]["name"] == "Fresh franchise"
    {:ok, current_revision} = Delivest.Storefront.Revisions.current("franchise")
    assert result["revisions"]["franchise"] == current_revision
  end

  test "menu load crossing stop expiry is retried before cache publication", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    category = insert(:category)
    product = insert(:product, category_id: category.id)
    Delivest.Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id)
    Delivest.Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)
    until = DateTime.utc_now() |> DateTime.add(2, :second) |> DateTime.truncate(:second)

    Repo.insert!(%Delivest.Net.ProductStop{
      branch_id: branch.id,
      product_id: product.id,
      source: "manual",
      until: until
    })

    refresh_revisions()
    owner = self()
    gate = :atomics.new(1, [])
    handler = "storefront-expiry-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:delivest, :repo, :query],
        fn _, _, metadata, _ ->
          if String.contains?(metadata[:query] || "", ~s(SELECT p0."until" FROM "product_stops")) and
               :atomics.compare_exchange(gate, 1, 0, 1) == :ok do
            send(owner, {:boundary_query, self()})

            receive do
              :continue -> :ok
            after
              5_000 -> :ok
            end
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    path = "/client/storefront/v1/bootstrap?slug=#{branch.slug}"
    task = Task.async(fn -> conn |> get(path) |> json_response(200) end)
    assert_receive {:boundary_query, loader}, 5_000
    Process.sleep(max(0, DateTime.diff(until, DateTime.utc_now(), :millisecond) + 100))
    send(loader, :continue)

    result = Task.await(task, 10_000)
    products = result["menu"] |> Enum.flat_map(& &1["products"])
    assert Enum.any?(products, &(&1["id"] == product.id))
  end

  test "one cold menu key is built once for one hundred simultaneous readers" do
    branch = insert(:branch, is_active: true)
    branch_id = branch.id
    refresh_revisions()
    params = %{"slug" => branch.slug, "locale" => "ru"}
    assert {:ok, _} = Delivest.Storefront.bootstrap(params)

    {:ok, keys} = Cachex.keys(:storefront_cache)

    Enum.each(keys, fn
      {:menu, ^branch_id, "ru", _} = key -> Cachex.del(:storefront_cache, key)
      _ -> :ok
    end)

    counter = :atomics.new(1, [])
    handler = "storefront-singleflight-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:delivest, :repo, :query],
        fn _, _, metadata, _ ->
          if String.contains?(metadata[:query] || "", ~s(SELECT p0."until" FROM "product_stops")) do
            :atomics.add_get(counter, 1, 1)
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    results =
      1..100
      |> Task.async_stream(fn _ -> Delivest.Storefront.bootstrap(params) end,
        max_concurrency: 100,
        timeout: 10_000
      )
      |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, {:ok, _}}, &1))
    assert :atomics.get(counter, 1) == 1
  end

  test "a thousand scoped menu revisions leave no old menu projections" do
    branch = insert(:branch, is_active: true)
    branch_id = branch.id
    refresh_revisions()

    for number <- 1..1000 do
      Cachex.put(:storefront_cache, {:menu, branch.id, "ru", "old-#{number}"}, %{menu: number})

      Repo.query!(
        "INSERT INTO storefront_revisions(section, scope, revision) VALUES ('menu', $1, 1) " <>
          "ON CONFLICT (section, scope) DO UPDATE SET revision = storefront_revisions.revision + 1",
        [branch.id]
      )

      refresh_worker()
    end

    {:ok, keys} = Cachex.keys(:storefront_cache)
    refute Enum.any?(keys, &match?({:menu, ^branch_id, _, _}, &1))
  end

  test "menu projection expires at the next stop boundary", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    category = insert(:category)
    product = insert(:product, category_id: category.id)
    Delivest.Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id)
    Delivest.Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)
    until = DateTime.utc_now() |> DateTime.add(3, :second) |> DateTime.truncate(:second)

    Repo.insert!(%Delivest.Net.ProductStop{
      branch_id: branch.id,
      product_id: product.id,
      source: "manual",
      until: until
    })

    refresh_revisions()
    path = "/client/storefront/v1/bootstrap?slug=#{branch.slug}"
    assert conn |> get(path) |> json_response(200)
    {:ok, keys} = Cachex.keys(:storefront_cache)
    menu_key = Enum.find(keys, &match?({:menu, _, _, _}, &1))
    assert {:ok, ttl} = Cachex.ttl(:storefront_cache, menu_key)
    assert ttl > 0 and ttl <= 3_000

    Process.sleep(max(0, DateTime.diff(until, DateTime.utc_now(), :millisecond) + 100))
    assert Cachex.get(:storefront_cache, menu_key) == {:ok, nil}

    result = conn |> recycle() |> get(path) |> json_response(200)
    products = result["menu"] |> Enum.flat_map(& &1["products"])
    assert Enum.any?(products, &(&1["id"] == product.id))
  end

  defp refresh_worker do
    send(Delivest.Storefront.Revisions, :refresh)
    :sys.get_state(Delivest.Storefront.Revisions)
  end

  defp revision(section, scope) do
    [[value]] =
      Repo.query!(
        """
        SELECT COALESCE(SUM(revision), 0)::bigint FROM (
          SELECT revision FROM storefront_revisions WHERE section = $1 AND scope = $2
          UNION ALL
          SELECT delta FROM storefront_revision_pending WHERE section = $1 AND scope = $2
        ) changes
        """,
        [section, scope]
      ).rows

    value
  end

  defp refresh_revisions do
    %{rows: rows} =
      Repo.query!(
        "SELECT e.epoch, r.section, r.scope, r.revision FROM storefront_epoch e LEFT JOIN storefront_revisions r ON true",
        []
      )

    epoch = rows |> hd() |> hd()

    revisions =
      rows
      |> Enum.reject(fn [_epoch, section | _] -> is_nil(section) end)
      |> Map.new(fn [_epoch, section, scope, revision] -> {{section, scope}, revision} end)

    :ets.insert(
      :storefront_revisions_snapshot,
      {:snapshot, revisions, epoch, System.monotonic_time(:millisecond)}
    )

    refresh_worker()
  end
end
