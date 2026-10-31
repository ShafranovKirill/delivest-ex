defmodule Delivest.Integrations.SmallHealthTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Integrations.{Dadata, Health, Zvonok}
  alias Delivest.Integrations.Dadata.Settings

  test "the Dadata check records ok and a rejected key" do
    Repo.insert!(%Settings{api_key: "key", enabled: true})

    Req.Test.stub(Delivest.HTTP.Client, fn conn -> Req.Test.json(conn, %{"suggestions" => []}) end)

    assert {:ok, %{status: :ok}} = Health.check(:dadata, nil)

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{})
    end)

    assert {:ok, %{status: :auth}} = Health.check(:dadata, nil)
    assert %{status: :auth} = Health.get(:dadata, nil)
  end

  test "the Dadata poller checks only an active integration" do
    assert :done = Dadata.Poller.poll("all")
    assert Health.get(:dadata, nil) == nil
  end

  test "Zvonok failures and recoveries are tracked on real calls" do
    insert(:zvonok_settings)

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{})
    end)

    assert {:error, _reason} = Zvonok.request_call("+79991234567")
    assert %{status: :auth} = Health.get(:zvonok, nil)

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{
        "status" => "ok",
        "data" => %{"call_id" => 1, "allowed_phones_for_call" => ["+78005553535"]}
      })
    end)

    assert {:ok, _call} = Zvonok.request_call("+79991234567")
    assert %{status: :ok} = Health.get(:zvonok, nil)
  end

  test "the Zvonok check needs complete settings" do
    assert {:error, :zvonok_not_configured} = Zvonok.health_check(%Zvonok.Settings{})
    insert(:zvonok_settings)
    assert :ok = Zvonok.health_check(Zvonok.get_settings())
  end
end
