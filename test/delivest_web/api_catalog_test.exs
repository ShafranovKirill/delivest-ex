defmodule DelivestWeb.ApiCatalogTest do
  use DelivestWeb.ConnCase, async: true

  alias DelivestWeb.ApiCatalog

  test "public and Scalar specs expose all selected routes with concrete contracts",
       %{
         conn: conn
       } do
    public = conn |> get("/api/openapi") |> json_response(200)
    scalar = conn |> recycle() |> get("/api/scalar/openapi") |> json_response(200)

    assert public["info"]["title"] == "My App"
    assert scalar["info"]["title"] == "Delivest API"

    assert scalar["x-delivest-contract-coverage"] == %{
             "routeCount" => length(ApiCatalog.routes()),
             "undocumentedCount" => length(ApiCatalog.missing())
           }

    for {method, path} <- ApiCatalog.routes() do
      assert get_in(scalar, ["paths", path, method]), "missing Scalar #{method} #{path}"
    end

    assert length(ApiCatalog.routes()) == 82
    assert ApiCatalog.missing() == []
    assert scalar["x-delivest-contract-coverage"]["undocumentedCount"] == 0

    for {method, path} <- ApiCatalog.routes() do
      contract = get_in(public, ["paths", path, method])
      assert contract["operationId"], "operationId missing for #{method} #{path}"
      assert contract["responses"] != %{}, "responses missing for #{method} #{path}"
      refute contract["x-delivest-contract-status"] == "undocumented"
      refute Map.has_key?(contract["responses"], "default")
    end

    order = get_in(public, ["paths", "/integrations/yandex-eda/order", "post"])
    assert order["security"] == [%{"yandexEdaBearer" => []}]
    assert order["requestBody"]["content"]["application/json"]["schema"]["oneOf"] |> length() == 3
    assert Map.has_key?(order["responses"], "406")

    assert get_in(public, [
             "paths",
             "/integrations/yandex-eda/order/{id}",
             "put",
             "responses",
             "422"
           ])

    refute get_in(public, ["paths", "/integrations/yandex-eda/order/{id}", "put", "requestBody"])

    assert get_in(public, [
             "paths",
             "/integrations/yandex-eda/menu/{restaurant_id}/composition",
             "get",
             "responses",
             "200",
             "content",
             "application/vnd.eats.menu.composition.v2+json"
           ])

    assert get_in(public, ["paths", "/integrations/crm/{provider}/{token}", "post", "security"]) ==
             []

    assert scalar["servers"] == [%{"url" => "/"}]
    assert scalar["tags"] |> Enum.map(& &1["name"]) |> hd() == "Health"

    staging = scalar["x-scalar-environments"]["staging"]["variables"]
    assert %{"name" => "baseUrl", "value" => ""} in staging
    assert %{"name" => "accessToken", "value" => ""} in staging

    complete = get_in(scalar, ["paths", "/client/auth/call/{id}/complete", "post"])
    assert complete["x-post-response"] =~ "data.access_token"

    assert get_in(scalar, ["paths", "/client/auth/refresh", "post", "x-post-response"]) =~
             "data.refresh_token"

    assert get_in(scalar, ["paths", "/client/me", "get", "x-pre-request"]) =~
             "pm.environment.get('accessToken')"

    refute get_in(scalar, ["paths", "/integrations/yandex-eda/order", "post", "x-pre-request"])
  end

  test "new and resolved contract gaps require a baseline update" do
    assert ApiCatalog.baseline_diff() == {[], []}
    assert ApiCatalog.baseline() == []

    assert ApiCatalog.baseline_diff([{"get", "/client/new"}]) ==
             {[{"get", "/client/new"}], []}
  end

  test "reference page loads the pinned client and uses the same-origin API", %{conn: conn} do
    conn = conn |> put_req_header("accept", "text/html") |> get("/api/reference")
    assert html_response(conn, 200) =~ "@scalar/api-reference@1.84.0"
    assert conn.resp_body =~ "url: '/api/scalar/openapi'"
    assert conn.resp_body =~ "agent: { disabled: true }"
    assert conn.resp_body =~ "proxyUrl: ''"
  end
end
