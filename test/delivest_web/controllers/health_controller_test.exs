defmodule DelivestWeb.HealthControllerTest do
  use DelivestWeb.ConnCase, async: true

  test "health answers without touching the database", %{conn: conn} do
    body = conn |> get(~p"/health") |> json_response(200)

    assert body["status"] == "ok"
    assert body["app"] == "delivest"
    assert body["version"] == Application.get_env(:delivest, :version, "dev")
  end

  test "ready reports the database and applied migrations", %{conn: conn} do
    body = conn |> get(~p"/ready") |> json_response(200)

    assert body["status"] == "ok"
    assert body["checks"] == %{"database" => "ok", "migrations" => "ok"}
  end
end
