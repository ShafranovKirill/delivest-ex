defmodule Delivest.Integrations.YandexEda.OrderAddressTest do
  use Delivest.DataCase, async: false

  alias Delivest.Integrations.Dadata.Settings
  alias Delivest.Integrations.YandexEda.OrderAddress

  setup do
    Repo.insert!(%Settings{api_key: "key", enabled: true})
    :ok
  end

  test "uses enrichment returned within the marketplace budget" do
    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{
        "suggestions" => [
          %{
            "value" => "Уточнённый адрес",
            "data" => %{"city" => "Москва", "street_with_type" => "Тверская ул", "house" => "1"}
          }
        ]
      })
    end)

    assert %{
             "formatted" => "Исходный адрес",
             "latitude" => 55.751,
             "longitude" => 37.611,
             "city" => "Москва",
             "street" => "Тверская ул",
             "house" => "1"
           } = OrderAddress.build(%{full: "Исходный адрес", latitude: 55.751, longitude: 37.611})
  end

  test "a slow provider preserves the original address and coordinates" do
    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      send(test_pid, {:provider_started, self()})

      receive do
        :release -> Req.Test.json(conn, %{"suggestions" => []})
      after
        5_000 -> Req.Test.json(conn, %{"suggestions" => []})
      end
    end)

    started = System.monotonic_time(:millisecond)

    assert %{
             "formatted" => "Исходный адрес",
             "latitude" => 55.752,
             "longitude" => 37.612
           } =
             OrderAddress.build(%{full: "Исходный адрес", latitude: 55.752, longitude: 37.612})

    assert System.monotonic_time(:millisecond) - started < 1_000
    assert_received {:provider_started, provider_pid}
    send(provider_pid, :release)
  end
end
