defmodule DelivestWeb.Client.StorefrontSectionsTest do
  use DelivestWeb.ConnCase, async: false

  import Delivest.Factory

  alias Delivest.Repo

  setup do
    Cachex.clear(:storefront_cache)
    :ok
  end

  test "responsive photo variants reach bootstrap, section and direct product", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    category = insert(:category)
    product = insert(:product, category_id: category.id)

    media =
      Repo.insert!(%Delivest.Media.File{
        bucket: "delivest",
        key: "product/variant-test.png",
        original_name: "variant-test.png",
        mime_type: "image/png",
        size: 100,
        context: :product,
        owner_id: product.id,
        is_private: false,
        thumb_key: "product/variant-test_thumb.webp",
        variant_keys: %{
          "192" => %{"key" => "product/variant-test_thumb_v2_192.webp", "width" => 192}
        }
      })

    product = product |> Ecto.Changeset.change(media_id: media.id) |> Repo.update!()
    Delivest.Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id)
    Delivest.Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)
    refresh_worker()

    bootstrap =
      conn |> get("/client/storefront/v1/bootstrap?slug=#{branch.slug}") |> json_response(200)

    section =
      conn
      |> recycle()
      |> get("/client/storefront/v1/sections/menu?branch_id=#{branch.id}")
      |> json_response(200)

    direct =
      conn
      |> recycle()
      |> get("/client/branches/#{branch.id}/products/#{product.id}")
      |> json_response(200)

    for offer <- [
          hd(hd(bootstrap["menu"])["products"]),
          hd(hd(section["data"])["products"]),
          direct["data"]
        ] do
      assert offer["photo_url"] =~ "/delivest/product/variant-test_thumb.webp"
      assert [%{"url" => url, "width" => 192}] = offer["photo_variants"]
      assert url =~ "/delivest/product/variant-test_thumb_v2_192.webp"
    end
  end

  test "conditional menu response is empty and scoped by locale and branch", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    other = insert(:branch, is_active: true)
    refresh_worker()
    path = "/client/storefront/v1/sections/menu?branch_id=#{branch.id}&locale=ru"
    first = get(conn, path)
    first_body = json_response(first, 200)
    assert is_list(first_body["data"])
    assert_section_contract(first_body)
    [tag] = get_resp_header(first, "etag")
    assert get_resp_header(first, "cache-control") == ["public, no-cache, must-revalidate"]

    conditional =
      first |> recycle() |> put_req_header("if-none-match", ~s("other", #{tag})) |> get(path)

    assert conditional.status == 304
    assert conditional.resp_body == ""
    assert get_resp_header(conditional, "etag") == [tag]
    assert get_resp_header(conditional, "x-storefront-valid-until") != []

    weak = String.replace_prefix(tag, "W/", "")

    assert first
           |> recycle()
           |> put_req_header("if-none-match", weak)
           |> get(path)
           |> Map.get(:status) == 304

    assert first
           |> recycle()
           |> put_req_header("if-none-match", "*")
           |> get(path)
           |> Map.get(:status) == 304

    english =
      first
      |> recycle()
      |> put_req_header("if-none-match", tag)
      |> get(String.replace(path, "locale=ru", "locale=en"))

    assert english.status == 200
    assert get_resp_header(english, "etag") != [tag]

    second =
      first
      |> recycle()
      |> put_req_header("if-none-match", tag)
      |> get(String.replace(path, branch.id, other.id))

    assert second.status == 200
    assert get_resp_header(second, "etag") != [tag]
  end

  test "menu change returns new content and validator", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    category = insert(:category)
    product = insert(:product, category_id: category.id)
    Delivest.Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id)
    Delivest.Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)
    refresh_worker()
    path = "/client/storefront/v1/sections/menu?branch_id=#{branch.id}&locale=ru"
    first = get(conn, path)

    assert Enum.any?(json_response(first, 200)["data"], fn category ->
             Enum.any?(category["products"], &(&1["id"] == product.id))
           end)

    [tag] = get_resp_header(first, "etag")

    Repo.insert!(%Delivest.Net.ProductStop{
      branch_id: branch.id,
      product_id: product.id,
      source: "manual"
    })

    refresh_worker()
    second = first |> recycle() |> put_req_header("if-none-match", tag) |> get(path)
    assert second.status == 200
    assert get_resp_header(second, "etag") != [tag]

    assert Enum.any?(json_response(second, 200)["data"], fn category ->
             Enum.any?(category["products"], &(&1["id"] == product.id and &1["stopped"]))
           end)
  end

  test "stop snapshot reuses active stops without crossing branch scope" do
    branch = insert(:branch, is_active: true)
    other = insert(:branch, is_active: true)
    product = insert(:product)
    group = Repo.insert!(%Delivest.Net.ModifierGroup{name: "Extras"})
    modifier = Repo.insert!(%Delivest.Net.Modifier{group_id: group.id, name: "Extra"})
    future = DateTime.utc_now() |> DateTime.add(60, :second) |> DateTime.truncate(:second)

    Repo.insert!(%Delivest.Net.ProductStop{
      branch_id: branch.id,
      product_id: product.id,
      source: "manual",
      until: future
    })

    Repo.insert!(%Delivest.Net.ModifierStop{
      branch_id: other.id,
      modifier_id: modifier.id,
      until: future
    })

    snapshot = Delivest.Net.PublicOffers.stop_snapshot(branch.id)
    assert MapSet.member?(snapshot.products, product.id)
    refute MapSet.member?(snapshot.modifiers, modifier.id)
    assert snapshot.boundary == future

    other_snapshot = Delivest.Net.PublicOffers.stop_snapshot(other.id)
    refute MapSet.member?(other_snapshot.products, product.id)
    assert MapSet.member?(other_snapshot.modifiers, modifier.id)
  end

  test "stop expiring between its snapshot and promotion read remains a stale boundary" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expired_during_build = DateTime.add(now, -1, :second)
    future_promotion = DateTime.add(now, 60, :second)

    assert Delivest.Storefront.menu_boundary(
             expired_during_build,
             [future_promotion, DateTime.add(now, -60, :second)],
             now
           ) == expired_during_build
  end

  test "inactive branch and invalid section never return 304", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    refresh_worker()
    path = "/client/storefront/v1/sections/stories?branch_id=#{branch.id}"
    [tag] = conn |> get(path) |> get_resp_header("etag")
    branch |> Ecto.Changeset.change(is_active: false) |> Repo.update!()
    refresh_worker()
    inactive = conn |> recycle() |> put_req_header("if-none-match", tag) |> get(path)
    assert json_response(inactive, 404)["error"] == "branch_not_found"
    assert get_resp_header(inactive, "cache-control") == ["no-store"]

    assert conn
           |> recycle()
           |> get("/client/storefront/v1/sections/menu?branch_id=bad")
           |> json_response(400)

    assert conn
           |> recycle()
           |> get("/client/storefront/v1/sections/unknown")
           |> json_response(404)
  end

  test "global sections retain complete branch fields and support 304", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    Repo.insert!(%Delivest.Identity.Branch.BranchInfo{branch_id: branch.id})
    refresh_worker()
    branches = get(conn, "/client/storefront/v1/sections/branches")
    body = json_response(branches, 200)
    assert_section_contract(body)
    data = body["data"]
    assert Enum.find(data, &(&1["id"] == branch.id))["branch_info"]
    [tag] = get_resp_header(branches, "etag")

    assert branches
           |> recycle()
           |> put_req_header("if-none-match", tag)
           |> get("/client/storefront/v1/sections/branches")
           |> Map.get(:status) == 304

    franchise =
      conn
      |> recycle()
      |> get("/client/storefront/v1/sections/franchise")
      |> json_response(200)

    assert_section_contract(franchise)
  end

  test "warm conditional section request performs no application SQL", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    refresh_worker()
    path = "/client/storefront/v1/sections/menu?branch_id=#{branch.id}&locale=ru"
    [tag] = conn |> get(path) |> get_resp_header("etag")
    handler = "storefront-section-warm-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:delivest, :repo, :query],
      fn _, _, metadata, owner ->
        if self() == owner and not String.contains?(metadata[:query] || "", "schema_migrations"),
          do: send(owner, :sql_query)
      end,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert conn
           |> recycle()
           |> put_req_header("if-none-match", tag)
           |> get(path)
           |> Map.get(:status) == 304

    refute_received :sql_query
  end

  test "temporal stop expiry changes the menu validator and content", %{conn: conn} do
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

    refresh_worker()
    path = "/client/storefront/v1/sections/menu?branch_id=#{branch.id}&locale=ru"
    first = get(conn, path)
    [tag] = get_resp_header(first, "etag")
    assert stopped?(json_response(first, 200)["data"], product.id)

    [{:snapshot, revisions, boundaries, epoch, _checked_at}] =
      :ets.lookup(:storefront_revisions_snapshot, :snapshot)

    wait_ms = max(0, DateTime.diff(until, DateTime.utc_now(), :millisecond) + 100)
    Process.send_after(self(), :boundary_elapsed, wait_ms)
    assert_receive :boundary_elapsed, wait_ms + 1_000
    second = first |> recycle() |> put_req_header("if-none-match", tag) |> get(path)
    assert second.status == 200
    [new_tag] = get_resp_header(second, "etag")
    assert new_tag != tag
    refute stopped?(json_response(second, 200)["data"], product.id)

    # A node with the pre-boundary snapshot must calculate the same phase even
    # when its local timer has not run. A fresh post-boundary snapshot agrees.
    :ets.insert(:storefront_revisions_snapshot, {
      :snapshot,
      revisions,
      boundaries,
      epoch,
      System.monotonic_time(:millisecond)
    })

    late = second |> recycle() |> put_req_header("if-none-match", tag) |> get(path)
    assert late.status == 200
    assert get_resp_header(late, "etag") == [new_tag]

    :sys.replace_state(Delivest.Storefront.Revisions, fn state ->
      Enum.each(state.boundaries, fn {_key, {_time, ref}} -> Process.cancel_timer(ref) end)
      %{state | boundaries: %{}, temporal: %{}, phases: %{}}
    end)

    refresh_worker()
    Cachex.clear(:storefront_cache)
    cold = late |> recycle() |> put_req_header("if-none-match", tag) |> get(path)
    assert cold.status == 200
    assert get_resp_header(cold, "etag") == [new_tag]

    assert cold
           |> recycle()
           |> put_req_header("if-none-match", new_tag)
           |> get(path)
           |> Map.get(:status) == 304

    revision_before_duplicate = Delivest.Storefront.Revisions.current("menu", branch.id)

    send(Delivest.Storefront.Revisions, {
      :boundary_reached,
      "menu",
      branch.id,
      DateTime.to_unix(until, :millisecond)
    })

    :sys.get_state(Delivest.Storefront.Revisions)
    assert Delivest.Storefront.Revisions.current("menu", branch.id) == revision_before_duplicate
  end

  test "promotion start and end produce stable menu validators", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    category = insert(:category)
    product = insert(:product, category_id: category.id, slug: "promo-temporal")
    Delivest.Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id)
    Delivest.Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)
    start_at = DateTime.utc_now() |> DateTime.add(3, :second) |> DateTime.truncate(:second)
    end_at = DateTime.add(start_at, 2, :second)

    insert(:promotion,
      branch_id: branch.id,
      starts_at: start_at,
      ends_at: end_at,
      rules: ~s(then price "promo-temporal" 50)
    )

    refresh_worker()

    path = "/client/storefront/v1/sections/menu?branch_id=#{branch.id}&locale=ru"
    first = get(conn, path)
    [before_tag] = get_resp_header(first, "etag")
    before_price = menu_price(json_response(first, 200)["data"], product.id)

    await_boundary(start_at)
    started = first |> recycle() |> put_req_header("if-none-match", before_tag) |> get(path)
    assert started.status == 200
    [active_tag] = get_resp_header(started, "etag")
    assert active_tag != before_tag
    active_price = menu_price(json_response(started, 200)["data"], product.id)
    assert active_price < before_price

    await_boundary(end_at)
    ended = started |> recycle() |> put_req_header("if-none-match", active_tag) |> get(path)
    assert ended.status == 200
    [ended_tag] = get_resp_header(ended, "etag")
    assert ended_tag != active_tag
    assert menu_price(json_response(ended, 200)["data"], product.id) == before_price

    refresh_worker()
    Cachex.clear(:storefront_cache)

    assert ended
           |> recycle()
           |> put_req_header("if-none-match", ended_tag)
           |> get(path)
           |> Map.get(:status) == 304
  end

  test "modifier stop expiry restores the menu offer", %{conn: conn} do
    alias Delivest.Net.{Modifier, ModifierGroup, ModifierStop, ProductModifierGroup}

    branch = insert(:branch, is_active: true)
    category = insert(:category)
    product = insert(:product, category_id: category.id)
    group = Repo.insert!(%ModifierGroup{name: "Size", min: 1, max: 1})
    modifier = Repo.insert!(%Modifier{group_id: group.id, name: "Large", price: 500})
    Repo.insert!(%ProductModifierGroup{group_id: group.id, product_id: product.id})
    Delivest.Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id)
    Delivest.Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id)
    until = DateTime.utc_now() |> DateTime.add(3, :second) |> DateTime.truncate(:second)
    Repo.insert!(%ModifierStop{branch_id: branch.id, modifier_id: modifier.id, until: until})
    refresh_worker()

    path = "/client/storefront/v1/sections/menu?branch_id=#{branch.id}&locale=ru"
    first = get(conn, path)
    [tag] = get_resp_header(first, "etag")
    assert modifier_stopped?(json_response(first, 200)["data"], product.id, modifier.id)

    await_boundary(until)
    second = first |> recycle() |> put_req_header("if-none-match", tag) |> get(path)
    assert second.status == 200
    refute modifier_stopped?(json_response(second, 200)["data"], product.id, modifier.id)
    assert get_resp_header(second, "etag") != [tag]
  end

  test "branch intake pause and load expiry change the branches validator", %{conn: conn} do
    alias Delivest.Identity.Branch.{BranchInfo, IntakeSettings}

    branch = insert(:branch, is_active: true)
    pause_until = DateTime.utc_now() |> DateTime.add(3, :second) |> DateTime.truncate(:second)
    load_until = DateTime.add(pause_until, 2, :second)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      intake: %IntakeSettings{
        paused_until: pause_until,
        load_until: load_until,
        load_minutes: 10
      }
    })

    refresh_worker()
    path = "/client/storefront/v1/sections/branches"
    first = get(conn, path)
    [pause_tag] = get_resp_header(first, "etag")

    await_boundary(pause_until)
    second = first |> recycle() |> put_req_header("if-none-match", pause_tag) |> get(path)
    assert second.status == 200
    [load_tag] = get_resp_header(second, "etag")
    assert load_tag != pause_tag

    await_boundary(load_until)
    third = second |> recycle() |> put_req_header("if-none-match", load_tag) |> get(path)
    assert third.status == 200
    assert get_resp_header(third, "etag") != [load_tag]
  end

  test "rating expiry changes the franchise validator and removes stale rating", %{conn: conn} do
    expires = DateTime.utc_now() |> DateTime.add(3, :second) |> DateTime.truncate(:second)

    Repo.insert!(%Delivest.Franchise.Rating{
      provider: :yandex,
      rating: 4.8,
      reviews_count: 15,
      fetched_at: DateTime.add(expires, -7, :day)
    })

    refresh_worker()
    path = "/client/storefront/v1/sections/franchise"
    first = get(conn, path)
    [tag] = get_resp_header(first, "etag")
    assert json_response(first, 200)["data"]["rating"] != nil

    await_boundary(expires)
    second = first |> recycle() |> put_req_header("if-none-match", tag) |> get(path)
    assert second.status == 200
    assert get_resp_header(second, "etag") != [tag]
    assert json_response(second, 200)["data"]["rating"] == nil
  end

  defp await_boundary(boundary) do
    wait_ms = max(0, DateTime.diff(boundary, DateTime.utc_now(), :millisecond) + 100)
    Process.send_after(self(), :boundary_elapsed, wait_ms)
    assert_receive :boundary_elapsed, wait_ms + 1_000
  end

  defp menu_price(categories, product_id) do
    categories
    |> Enum.flat_map(& &1["products"])
    |> Enum.find(&(&1["id"] == product_id))
    |> Map.fetch!("price")
  end

  defp modifier_stopped?(categories, product_id, modifier_id) do
    categories
    |> Enum.flat_map(& &1["products"])
    |> Enum.find(&(&1["id"] == product_id))
    |> Map.fetch!("modifier_groups")
    |> Enum.flat_map(& &1["modifiers"])
    |> Enum.find(&(&1["id"] == modifier_id))
    |> Map.fetch!("stopped")
  end

  defp stopped?(categories, product_id) do
    Enum.any?(categories, fn category ->
      Enum.any?(category["products"], &(&1["id"] == product_id and &1["stopped"]))
    end)
  end

  defp refresh_worker do
    send(Delivest.Storefront.Revisions, :refresh)
    :sys.get_state(Delivest.Storefront.Revisions)
  end

  defp assert_section_contract(body) do
    spec = DelivestWeb.OpenApi.spec()

    schema =
      spec.paths["/client/storefront/v1/sections/{section}"].get.responses[200].content[
        "application/json"
      ].schema

    assert {:ok, _} = OpenApiSpex.cast_value(body, schema, spec)
  end
end
