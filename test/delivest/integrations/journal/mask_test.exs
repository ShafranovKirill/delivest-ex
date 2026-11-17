defmodule Delivest.Integrations.Journal.MaskTest do
  use ExUnit.Case, async: true

  alias Delivest.Integrations.Journal.Mask

  test "secret keys are masked deep in maps and lists" do
    body = %{
      "client_secret" => "s",
      "items" => [%{"apiLogin" => "l", "name" => "Борщ"}],
      "access_token" => "t",
      "amount" => 100
    }

    assert body |> Mask.body() |> Jason.decode!() == %{
             "client_secret" => "***",
             "items" => [%{"apiLogin" => "***", "name" => "Борщ"}],
             "access_token" => "***",
             "amount" => 100
           }
  end

  test "form params keep their order and mask secrets" do
    assert Mask.body([{"secret", "s"}, {"name", "Борщ"}]) == "secret=***&name=Борщ"
    assert Mask.body(api_key: "k", count: 1) == "api_key=***&count=1"
  end

  test "json is masked and opaque payloads are withheld" do
    assert Mask.body(~s({"token":"t","ok":true})) == ~s({"ok":true,"token":"***"})
    assert Mask.body("plain text") == "<10 bytes>"
    assert Mask.body(<<255, 0>>) == "<2 bytes>"
    assert Mask.body(nil) == nil
  end

  test "query params and path params are masked" do
    assert Mask.url("https://x.ru/api?public_key=k&phone=79990001122") ==
             "https://x.ru/api?public_key=%2A%2A%2A&phone=79990001122"

    assert Mask.path("/integrations/crm/frontpad/abc", %{
             "provider" => "frontpad",
             "token" => "abc"
           }) ==
             "/integrations/crm/frontpad/***"
  end

  test "long bodies are truncated" do
    assert %{name: String.duplicate("a", 20_000)} |> Mask.body() |> String.length() == 16_000
  end

  test "Measurement Protocol and OAuth secrets are masked recursively" do
    masked =
      Mask.body(%{
        "ms" => "measurement-secret",
        "measurement_tokens" => ["token-one", %{"value" => "token-two"}],
        "items" => [%{"refresh_token" => "refresh-secret", "client_secret" => "oauth-secret"}],
        "count" => 1
      })

    assert Jason.decode!(masked) == %{
             "ms" => "***",
             "measurement_tokens" => "***",
             "items" => [%{"refresh_token" => "***", "client_secret" => "***"}],
             "count" => 1
           }
  end

  test "encoded forms and query strings mask short and encoded secret names" do
    masked = Mask.body("grant_type=refresh_token&refresh_token=refresh-secret&%6Ds=mp-secret")

    assert URI.decode_query(masked) == %{
             "grant_type" => "refresh_token",
             "refresh_token" => "***",
             "ms" => "***"
           }

    url = Mask.url("https://user:password@x.test/collect?ms=mp-secret&tid=123#token")
    refute url =~ "mp-secret"
    refute url =~ "password"
    refute url =~ "#token"
    assert url =~ "tid=123"

    assert Mask.body(
             "code=authorization-secret&code_verifier=pkce-secret&grant_type=authorization_code"
           )
           |> URI.decode_query() == %{
             "code" => "***",
             "code_verifier" => "***",
             "grant_type" => "authorization_code"
           }
  end

  test "multipart and unknown structured values never inspect file contents or paths" do
    assert Mask.body([{"file", {"private-file.csv", "ClientId,token-secret"}}, {"ms", "mp"}]) ==
             "file=<structured body>&ms=***"

    refute Mask.body("--boundary\r\nname=ms\r\n\r\nmp-secret\r\n--boundary") =~ "mp-secret"

    assert Mask.body(%{payload: {"private-file.csv", "token-secret"}}) ==
             ~s({"payload":"<multipart body>"})
  end

  test "external advertising identifiers are masked without hiding ordinary IDs" do
    masked = Mask.body(%{cid: "c", client_id: "c", ClientID: "c", yclid: "y", UserId: "u", user_id: "u", id: "ordinary"})
    assert Jason.decode!(masked) == %{
             "cid" => "***", "client_id" => "***", "ClientID" => "***", "yclid" => "***",
             "UserId" => "***", "user_id" => "***", "id" => "ordinary"
           }
  end
end
