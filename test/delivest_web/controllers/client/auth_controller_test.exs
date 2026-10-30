defmodule DelivestWeb.Client.AuthControllerTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  alias DelivestWeb.ClientToken

  @phone "+79991234567"

  setup %{conn: conn} do
    insert(:zvonok_settings)
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

  test "postback takes the zvonok macro names", %{conn: conn} do
    start_call(conn, 2002)

    assert %{"result" => "success"} =
             conn
             |> get("/integrations/zvonok/zvonok-token?ct_call_id=2002&ct_phone=79991234567")
             |> json_response(200)
  end

  test "postback without the call parameters is logged with what came", %{conn: conn} do
    start_call(conn, 3003)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert %{"result" => "ignored"} =
                 conn |> get("/integrations/zvonok/zvonok-token?foo=bar") |> json_response(200)
      end)

    assert log =~ "zvonok webhook matched no pending sign-in"
    assert log =~ ~s("foo" => "bar")
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

  test "turned off sign-in leaves everyone a guest", %{conn: conn} do
    client = insert(:client)
    %{access_token: access, refresh_token: refresh} = ClientToken.issue(client.id)
    Delivest.Repo.update_all(Delivest.Integrations.Zvonok.Settings, set: [enabled: false])

    assert %{"data" => %{"client_auth" => false}} =
             conn |> get(~p"/client/franchise") |> json_response(200)

    assert %{"error" => "auth_disabled"} =
             conn |> post(~p"/client/auth/call", %{phone: @phone}) |> json_response(403)

    assert %{"error" => "auth_disabled"} =
             conn
             |> post(~p"/client/auth/refresh", %{refresh_token: refresh})
             |> json_response(403)

    assert %{"error" => "unauthorized"} =
             build_conn()
             |> put_req_header("authorization", "Bearer " <> access)
             |> get(~p"/client/me")
             |> json_response(401)
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

  test "an active unconfirmed call is reused without a new Zvonok request", %{conn: conn} do
    first = start_call(conn)
    Req.Test.stub(Delivest.HTTP.Client, fn _conn -> flunk("Zvonok must not be called again") end)

    second =
      conn |> post(~p"/client/auth/call", %{phone: "8 (999) 123-45-67"}) |> json_response(200)

    assert second["data"]["confirmation_id"] == first["confirmation_id"]
    assert second["data"]["call_number"] == first["call_number"]
  end

  test "the fourth call request for a phone in ten minutes gets 429", %{conn: conn} do
    for n <- 1..3 do
      {:ok, _} =
        Delivest.Identity.PhoneConfirmations.create(%{
          phone: @phone,
          session_id: "other-#{n}",
          call_id: "c-#{n}",
          call_number: "7800"
        })
    end

    stub_zvonok(1)

    conn = post(conn, ~p"/client/auth/call", %{phone: "8 (999) 123-45-67"})

    assert %{"error" => "too_many_requests", "details" => %{"retry_after" => wait}} =
             json_response(conn, 429)

    assert wait in 1..600
    assert [_] = get_resp_header(conn, "retry-after")

    stub_zvonok(2)

    assert %{"data" => %{"confirmation_id" => _}} =
             build_conn()
             |> put_req_header(
               "x-forwarded-for",
               "auth-other-#{System.unique_integer([:positive])}"
             )
             |> with_session()
             |> post(~p"/client/auth/call", %{phone: "+79990000001"})
             |> json_response(200)
  end

  test "integration webhooks allow any origin" do
    conn =
      build_conn()
      |> put_req_header("origin", "https://zvonok.com")
      |> get("/integrations/zvonok/wrong")

    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
  end

  describe "flash call mode" do
    setup do
      Delivest.Repo.update_all(Delivest.Integrations.Zvonok.Settings,
        set: [login_call_mode: :flash]
      )

      :ok
    end

    defp start_flash(conn) do
      conn |> post(~p"/client/auth/call", %{phone: "8 (999) 123-45-67"}) |> json_response(200)
    end

    defp code_of(id), do: Delivest.Repo.get!(Delivest.Identity.PhoneConfirmation, id).code

    test "starts without a number to call and signs in with the code", %{conn: conn} do
      assert %{"data" => %{"mode" => "flash", "call_number" => nil, "confirmation_id" => id}} =
               start_flash(conn)

      assert conn |> post(~p"/client/auth/call/#{id}/complete") |> json_response(202)

      assert %{"data" => %{"status" => "confirmed"}} =
               conn
               |> post(~p"/client/auth/call/#{id}/confirm", %{code: code_of(id)})
               |> json_response(200)

      assert %{"data" => %{"status" => "confirmed", "access_token" => _}} =
               conn |> post(~p"/client/auth/call/#{id}/complete") |> json_response(200)
    end

    test "a wrong code costs an attempt and three of them lock the confirmation", %{conn: conn} do
      %{"data" => %{"confirmation_id" => id}} = start_flash(conn)
      wrong = if code_of(id) == "0000", do: "1111", else: "0000"

      for left <- [2, 1, 0] do
        assert %{"error" => "invalid_code", "details" => %{"attempts_left" => ^left}} =
                 conn
                 |> post(~p"/client/auth/call/#{id}/confirm", %{code: wrong})
                 |> json_response(422)
      end

      assert conn
             |> post(~p"/client/auth/call/#{id}/confirm", %{code: code_of(id)})
             |> json_response(429)

      assert conn |> post(~p"/client/auth/call/#{id}/complete") |> json_response(202)
    end

    test "another session cannot confirm", %{conn: conn} do
      %{"data" => %{"confirmation_id" => id}} = start_flash(conn)

      other =
        Phoenix.ConnTest.build_conn()
        |> put_req_header("x-forwarded-for", "auth-#{System.unique_integer([:positive])}")
        |> with_session()

      assert other
             |> post(~p"/client/auth/call/#{id}/confirm", %{code: code_of(id)})
             |> json_response(404)
    end

    test "a repeated start returns the same confirmation", %{conn: conn} do
      %{"data" => %{"confirmation_id" => id}} = start_flash(conn)
      assert %{"data" => %{"confirmation_id" => ^id}} = start_flash(conn)
    end
  end
end
