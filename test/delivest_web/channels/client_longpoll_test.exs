defmodule DelivestWeb.ClientLongPollTest do
  use DelivestWeb.ConnCase, async: false

  alias Delivest.Identity.{ClientAuth, PhoneConfirmations}
  alias DelivestWeb.ClientToken

  @origin "http://localhost:3000"
  @phone "+79991234567"

  defp longpoll(method, query, body \\ nil) do
    build_conn()
    |> put_req_header("origin", @origin)
    |> put_req_header("content-type", "application/json")
    |> dispatch(DelivestWeb.Endpoint, method, "/socket/longpoll?" <> query, body)
  end

  test "the client socket works over long polling when websockets are blocked" do
    {:ok, confirmation} =
      PhoneConfirmations.create(%{phone: @phone, session_id: "sess-lp", call_id: "lp-1"})

    :ok = ClientAuth.confirm_call("lp-1", @phone)
    token = ClientToken.issue_socket("sess-lp", nil)

    connect = URI.encode_query(%{"token" => token, "vsn" => "2.0.0"})
    handshake = longpoll(:get, connect <> "&")
    assert %{"status" => 410, "token" => session} = json_response(handshake, 200)
    assert get_resp_header(handshake, "access-control-allow-origin") == ["*"]

    join = Jason.encode!(["1", "1", "auth:#{confirmation.id}", "phx_join", %{}])
    params = connect <> "&" <> URI.encode_query(%{"token" => session})
    assert %{"status" => 200} = :post |> longpoll(params, join) |> json_response(200)

    messages = receive_messages(params, [])
    assert Enum.any?(messages, &match?([_, _, _, "phx_reply", %{"status" => "ok"}], &1))

    assert [_, _, _, "confirmed", %{"status" => "confirmed", "access_token" => access}] =
             Enum.find(messages, &match?([_, _, _, "confirmed", _], &1))

    assert {:ok, _client_id} = ClientToken.verify_access(access)
  end

  test "long polling from a foreign origin is refused" do
    token = ClientToken.issue_socket("sess-lp", nil)

    conn =
      build_conn()
      |> put_req_header("origin", "https://evil.example.com")
      |> get("/socket/longpoll", %{"token" => token, "vsn" => "2.0.0"})

    assert %{"status" => 403} = json_response(conn, 200)
  end

  defp receive_messages(params, acc, tries \\ 5)
  defp receive_messages(_params, acc, 0), do: acc

  defp receive_messages(params, acc, tries) do
    messages =
      case :get |> longpoll(params) |> json_response(200) do
        %{"status" => 200, "messages" => messages} -> Enum.map(messages, &Jason.decode!/1)
        _ -> []
      end

    acc = acc ++ messages

    if Enum.any?(acc, &match?([_, _, _, "confirmed", _], &1)),
      do: acc,
      else: receive_messages(params, acc, tries - 1)
  end
end
