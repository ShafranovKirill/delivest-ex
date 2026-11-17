defmodule Delivest.HTTP.ClientTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Delivest.HTTP.Client

  for status <- [200, 201, 202] do
    test "full response retains status #{status} and provider headers" do
      status = unquote(status)

      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("retryin", "15")
        |> Plug.Conn.put_resp_header("requestid", "report-request")
        |> Plug.Conn.send_resp(status, "Date\tCost\n2026-11-17\t1230000\n")
      end)

      assert {:ok, %{status: ^status, headers: headers, body: body}} =
               Client.post("/reports", %{}, base_url: "https://direct.test", response: :full)

      assert headers["retryin"] == ["15"]
      assert headers["requestid"] == ["report-request"]
      assert body == "Date\tCost\n2026-11-17\t1230000\n"
    end
  end

  test "default body and full-mode errors preserve existing contracts" do
    Req.Test.stub(Client, &Req.Test.json(&1, %{"ok" => true}))
    assert {:ok, %{"ok" => true}} = Client.get("https://legacy.test")

    Req.Test.stub(Client, &Plug.Conn.send_resp(&1, 429, "rate limited"))

    assert {:error, {:http_error, 429, "rate limited"}} =
             Client.get("https://direct.test", [], response: :full)
  end

  test "HTTP logs mask URL and structured error secrets while caller receives the response" do
    Req.Test.stub(Client, fn conn ->
      conn
      |> Plug.Conn.put_status(401)
      |> Req.Test.json(%{
        "ms" => "mp-response-secret",
        "measurement_tokens" => ["generated-secret"],
        "refresh_token" => "refresh-response-secret",
        "error" => "unauthorized"
      })
    end)

    log =
      capture_log([level: :info], fn ->
        assert {:error, {:http_error, 401, %{"ms" => "mp-response-secret"}}} =
                 Client.get("https://metrika.test/collect?ms=mp-query-secret", [],
                   headers: [{"authorization", "OAuth authorization-secret"}]
                 )
      end)

    for secret <- [
          "mp-query-secret",
          "mp-response-secret",
          "generated-secret",
          "refresh-response-secret",
          "authorization-secret"
        ] do
      refute log =~ secret
    end

    assert log =~ "unauthorized"
  end

  test "raw multipart errors are opaque in logs" do
    Req.Test.stub(Client, &Plug.Conn.send_resp(&1, 500, "--part\r\nms=raw-secret\r\n--part"))

    log =
      capture_log(fn ->
        assert {:error, {:http_error, 500, _}} = Client.get("https://metrika.test")
      end)

    refute log =~ "raw-secret"
    assert log =~ "bytes>"
  end

  test "connection failure masks OAuth callback parameters in logs and keeps safe error details" do
    Req.Test.stub(Client, &Req.Test.transport_error(&1, :econnrefused))

    log =
      capture_log([level: :info], fn ->
        assert {:error, {:connection_error, "connection refused", :econnrefused}} =
                 Client.get(
                   "https://oauth.test/token?code=oauth-secret&code_verifier=pkce-secret"
                 )
      end)

    refute log =~ "oauth-secret"
    refute log =~ "pkce-secret"
    assert log =~ "econnrefused"
  end

  test "unexpected exception details cannot leak through logs or returned connection errors" do
    Req.Test.stub(Client, fn conn ->
      Plug.Conn.put_private(
        conn,
        :req_test_exception,
        RuntimeError.exception("token=exception-secret")
      )
    end)

    log =
      capture_log(fn ->
        assert {:error, {:connection_error, "HTTP connection failed", :unknown}} =
                 Client.get("https://oauth.test/token")
      end)

    refute log =~ "exception-secret"
  end
end
