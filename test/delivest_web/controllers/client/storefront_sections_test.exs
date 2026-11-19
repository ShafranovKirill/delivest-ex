defmodule DelivestWeb.Client.StorefrontSectionsTest do
  use DelivestWeb.ConnCase, async: false

  import Delivest.Factory

  alias Delivest.Repo

  setup do
    Cachex.clear(:storefront_cache)
    :ok
  end

  test "conditional menu response is empty and scoped by locale and branch", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    other = insert(:branch, is_active: true)
    refresh_worker()
    path = "/client/storefront/v1/sections/menu?branch_id=#{branch.id}&locale=ru"
    first = get(conn, path)
    assert is_list(json_response(first, 200)["data"])
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
    data = json_response(branches, 200)["data"]
    assert Enum.find(data, &(&1["id"] == branch.id))["branch_info"]
    [tag] = get_resp_header(branches, "etag")

    assert branches
           |> recycle()
           |> put_req_header("if-none-match", tag)
           |> get("/client/storefront/v1/sections/branches")
           |> Map.get(:status) == 304

    assert conn
           |> recycle()
           |> get("/client/storefront/v1/sections/franchise")
           |> json_response(200)
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

    wait_ms = max(0, DateTime.diff(until, DateTime.utc_now(), :millisecond) + 100)
    Process.send_after(self(), :boundary_elapsed, wait_ms)
    assert_receive :boundary_elapsed, wait_ms + 1_000
    second = first |> recycle() |> put_req_header("if-none-match", tag) |> get(path)
    assert second.status == 200
    assert get_resp_header(second, "etag") != [tag]
    refute stopped?(json_response(second, 200)["data"], product.id)
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
end
