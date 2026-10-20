defmodule DelivestWeb.Integrations.FrontpadWebhookControllerTest do
  use DelivestWeb.ConnCase, async: true

  test "unknown tokens are rejected", %{conn: conn} do
    body =
      %{"action" => "change_status", "order_id" => 1, "status" => 3}
      |> then(&post(conn, ~p"/integrations/frontpad/unknown", &1))
      |> json_response(404)

    assert body == %{"result" => "error"}
  end

  test "other actions are acknowledged and ignored", %{conn: conn} do
    assert %{"result" => "ignored"} =
             conn
             |> post(~p"/integrations/frontpad/any", %{"action" => "other"})
             |> json_response(200)
  end
end
