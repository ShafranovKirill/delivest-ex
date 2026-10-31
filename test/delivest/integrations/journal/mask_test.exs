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

  test "json text is masked like a map, other text is kept" do
    assert Mask.body(~s({"token":"t","ok":true})) == ~s({"ok":true,"token":"***"})
    assert Mask.body("plain text") == "plain text"
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
    assert "a" |> String.duplicate(20_000) |> Mask.body() |> String.length() == 16_000
  end
end
