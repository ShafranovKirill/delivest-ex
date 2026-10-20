defmodule DelivestWeb.Client.AuthControllerTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  alias DelivestWeb.ClientToken

  @phone "+79991234567"

  setup %{conn: conn} do
    conn = put_req_header(conn, "x-forwarded-for", "auth-#{System.unique_integer([:positive])}")
    %{conn: with_session(conn)}
  end

  defp with_session(conn) do
    conn |> get(~p"/client/branches") |> recycle_keep_ip(conn)
  end

  defp recycle_keep_ip(conn, source) do
    conn
    |> recycle()
    |> put_req_header("x-forwarded-for", hd(get_req_header(source, "x-forwarded-for")))
  end

  defp stub_zvonok(call_id) do
    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      assert conn.request_path == "/manager/cabapi_external/api/v1/phones/confirm/"

      Req.Test.json(conn, %{
        "status" => "ok",
        "data" => %{
          "call_id" => call_id,
          "phone" => @phone,
          "allowed_phones_for_call" => ["+78005553535"]
        }
      })
    end)
  end

  defp start_call(conn, call_id \\ 555) do
    stub_zvonok(call_id)

    body =
      conn |> post(~p"/client/auth/call", %{phone: "8 (999) 123-45-67"}) |> json_response(200)

    body["data"]
  end

  defp postback(conn, call_id, phone \\ @phone) do
    get(
      conn,
      "/integrations/zvonok/zvonok-token?call_id=#{call_id}&phone=#{URI.encode_www_form(phone)}"
    )
  end

  test "socket token carries the session and the signed in client", %{conn: conn} do
    client = insert(:client)

    session_id =
      conn |> Plug.Conn.fetch_cookies() |> Map.fetch!(:req_cookies) |> Map.fetch!("session_id")

    token =
      conn |> get(~p"/client/socket_token") |> json_response(200) |> get_in(["data", "token"])

    assert {:ok, %{session_id: ^session_id, client_id: nil}} = ClientToken.verify_socket(token)

    %{access_token: access} = ClientToken.issue(client.id)

    token =
      conn
      |> put_req_header("authorization", "Bearer " <> access)
      |> get(~p"/client/socket_token")
      |> json_response(200)
      |> get_in(["data", "token"])

    assert {:ok, %{client_id: client_id}} = ClientToken.verify_socket(token)
    assert client_id == client.id
  end

  test "socket token of a brand new visitor has the new session" do
    conn = build_conn() |> get(~p"/client/socket_token")
    session_id = conn.resp_cookies["session_id"].value
    token = conn |> json_response(200) |> get_in(["data", "token"])
    assert {:ok, %{session_id: ^session_id}} = ClientToken.verify_socket(token)
  end

  test "full call confirmation flow issues working tokens", %{conn: conn} do
    data = start_call(conn)
    assert data["call_number"] == "+78005553535"

    pending = conn |> post(~p"/client/auth/call/#{data["confirmation_id"]}/complete")
    assert %{"data" => %{"status" => "pending"}} = json_response(pending, 202)

    assert %{"result" => "success"} = conn |> postback(555) |> json_response(200)

    session =
      conn
      |> post(~p"/client/auth/call/#{data["confirmation_id"]}/complete")
      |> json_response(200)
      |> Map.fetch!("data")

    assert session["status"] == "confirmed"
    assert session["client"]["phone"] == @phone

    me =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> session["access_token"])
      |> get(~p"/client/me")
      |> json_response(200)

    assert me["data"]["phone"] == @phone

    refreshed =
      build_conn()
      |> post(~p"/client/auth/refresh", %{refresh_token: session["refresh_token"]})
      |> json_response(200)

    assert refreshed["data"]["client"]["id"] == session["client"]["id"]

    assert %{"error" => "confirmation_not_found"} =
             conn
             |> post(~p"/client/auth/call/#{data["confirmation_id"]}/complete")
             |> json_response(404)
  end

  test "confirmation cannot be completed from another session", %{conn: conn} do
    data = start_call(conn, 777)
    postback(conn, 777)

    other = with_session(put_req_header(build_conn(), "x-forwarded-for", "other-ip"))

    assert %{"error" => "confirmation_not_found"} =
             other
             |> post(~p"/client/auth/call/#{data["confirmation_id"]}/complete")
             |> json_response(404)
  end

  test "postback for another phone does not confirm", %{conn: conn} do
    data = start_call(conn, 888)

    assert %{"result" => "ignored"} = conn |> postback(888, "+79990000000") |> json_response(200)

    assert conn
           |> post(~p"/client/auth/call/#{data["confirmation_id"]}/complete")
           |> json_response(202)
  end

  test "postback accepts phone with plus decoded as space", %{conn: conn} do
    data = start_call(conn, 999)

    assert %{"result" => "success"} =
             conn
             |> get("/integrations/zvonok/zvonok-token?call_id=999&phone=+79991234567")
             |> json_response(200)

    assert conn
           |> post(~p"/client/auth/call/#{data["confirmation_id"]}/complete")
           |> json_response(200)
  end

  test "postback works regardless of the accept header", %{conn: conn} do
    start_call(conn, 1001)

    assert %{"result" => "success"} =
             conn
             |> put_req_header("accept", "text/html")
             |> postback(1001)
             |> json_response(200)
  end

  test "unknown webhook token is rejected", %{conn: conn} do
    assert %{"result" => "error"} =
             conn |> get("/integrations/zvonok/wrong?call_id=1") |> json_response(404)
  end

  test "invalid phone is rejected", %{conn: conn} do
    assert %{"error" => "invalid_phone"} =
             conn |> post(~p"/client/auth/call", %{phone: "123"}) |> json_response(422)
  end

  test "response without a number to call is reported", %{conn: conn} do
    Req.Test.stub(
      Delivest.HTTP.Client,
      &Req.Test.json(&1, %{"status" => "ok", "data" => %{"call_id" => 1}})
    )

    assert %{"error" => "call_failed"} =
             conn |> post(~p"/client/auth/call", %{phone: @phone}) |> json_response(503)
  end

  test "zvonok error is reported", %{conn: conn} do
    Req.Test.stub(
      Delivest.HTTP.Client,
      &Req.Test.json(&1, %{"status" => "error", "data" => "bad key"})
    )

    assert %{"error" => "call_failed"} =
             conn |> post(~p"/client/auth/call", %{phone: @phone}) |> json_response(503)
  end

  test "blocked clients cannot refresh", %{conn: conn} do
    client = insert(:client, status: :blocked)
    %{refresh_token: token} = ClientToken.issue(client.id)

    assert %{"error" => "client_blocked"} =
             conn |> post(~p"/client/auth/refresh", %{refresh_token: token}) |> json_response(403)
  end

  test "invalid tokens are rejected", %{conn: conn} do
    assert %{"error" => "invalid_refresh_token"} =
             conn
             |> post(~p"/client/auth/refresh", %{refresh_token: "nope"})
             |> json_response(401)

    assert %{"error" => "unauthorized"} =
             conn
             |> put_req_header("authorization", "Bearer nope")
             |> get(~p"/client/orders/active")
             |> json_response(401)

    assert %{"error" => "unauthorized"} = conn |> get(~p"/client/me") |> json_response(401)
  end

  test "integration webhooks allow any origin" do
    conn =
      build_conn()
      |> put_req_header("origin", "https://zvonok.com")
      |> get("/integrations/zvonok/wrong")

    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
  end
end
