defmodule DelivestWeb.Integrations.CrmWebhookControllerTest do
  use DelivestWeb.ConnCase, async: true

  test "unknown tokens are rejected", %{conn: conn} do
    body =
      %{"action" => "change_status", "order_id" => 1, "status" => 3}
      |> then(&post(conn, ~p"/integrations/crm/frontpad/unknown", &1))
      |> json_response(404)

    assert body == %{"result" => "error"}
  end

  test "other actions are acknowledged and ignored", %{conn: conn} do
    assert %{"result" => "ignored"} =
             conn
             |> post(~p"/integrations/crm/frontpad/any", %{"action" => "other"})
             |> json_response(200)
  end

  test "unknown providers are rejected", %{conn: conn} do
    assert %{"result" => "error"} =
             conn
             |> post(~p"/integrations/crm/unknown/any", %{"action" => "change_status"})
             |> json_response(404)
  end

  test "incoming webhooks are journaled without the token", %{conn: conn} do
    post(conn, ~p"/integrations/crm/frontpad/secret-token", %{"action" => "other"})

    assert [request] = Delivest.Integrations.Journal.list(:frontpad, nil)
    assert request.direction == :in
    assert request.url == "/integrations/crm/frontpad/***"
    assert request.status == 200
    assert Jason.decode!(request.request) == %{"action" => "other"}
    assert Jason.decode!(request.response) == %{"result" => "ignored"}
  end
end
