defmodule DelivestWeb.Client.CapabilitiesControllerTest do
  use DelivestWeb.ConnCase, async: true

  test "public capabilities bootstrap a session and describe the version one contract", %{
    conn: conn
  } do
    conn = get(conn, ~p"/client/capabilities")

    assert %{
             "api_version" => 1,
             "order_event_version" => 1,
             "money_unit" => "kopeck",
             "timestamp_format" => "RFC3339",
             "features" => ["checkout_idempotency", "cart_revision"],
             "push" => %{"web_push" => true, "apns_fcm" => false},
             "deprecation" => nil
           } = json_response(conn, 200)

    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert conn.resp_cookies["session_id"].value != ""
  end

  test "OpenAPI advertises public capabilities without an app version header" do
    operation = DelivestWeb.OpenApi.spec().paths["/client/capabilities"].get

    assert operation.operationId
    refute Enum.any?(operation.parameters || [], &(&1.name == "X-App-Version"))
    assert operation.responses[200]
  end

  test "version one checkout request keeps the frozen pre S3 required fields" do
    spec = DelivestWeb.OpenApi.spec()
    request = spec.components.schemas["CreateOrderRequest"]
    operation = spec.paths["/client/orders"].post

    assert request.required == [:cart_id, :branch_id]
    refute :cart_revision in request.required
    refute Enum.any?(operation.parameters || [], &(&1.required && &1.name == "Idempotency-Key"))
  end
end
