defmodule Delivest.Integrations.DadataTest do
  use Delivest.DataCase, async: false

  alias Delivest.Integrations.Dadata
  alias Delivest.Integrations.Dadata.Settings

  defp configure(attrs \\ %{}),
    do: Repo.insert!(struct(%Settings{api_key: "key", enabled: true}, attrs))

  defp suggestion(street, house) do
    %{
      "value" => "#{street}, д #{house}",
      "data" => %{
        "city" => "Тюмень",
        "street_with_type" => street,
        "house" => house,
        "block_type" => "к",
        "block" => "2",
        "geo_lat" => "57.153",
        "geo_lon" => "65.534",
        "house_fias_id" => "6f3d1b6a-2b4e-4c1e-9a3f-0d8c5e7b9a11",
        "postal_code" => "625000",
        "city_district_with_type" => "Центральный р-н",
        "qc_geo" => "0"
      }
    }
  end

  test "suggests addresses inside the city and caches them" do
    configure()
    query = "республики #{System.unique_integer([:positive])}"
    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        test_pid,
        {:request, Plug.Conn.get_req_header(conn, "authorization"), Jason.decode!(body)}
      )

      Req.Test.json(conn, %{"suggestions" => [suggestion("ул Республики", "10")]})
    end)

    expected = [
      %{
        value: "ул Республики, д 10",
        city: "Тюмень",
        street: "ул Республики",
        house: "10 к 2",
        latitude: 57.153,
        longitude: 65.534,
        fias_id: "6f3d1b6a-2b4e-4c1e-9a3f-0d8c5e7b9a11",
        postal_code: "625000",
        district: "Центральный р-н",
        geo_precision: 0
      }
    ]

    assert {:ok, ^expected} = Dadata.suggest(query, "г. Тюмень")
    assert_received {:request, ["Token key"], %{"locations" => [%{"city" => "Тюмень"}]}}

    assert {:ok, ^expected} = Dadata.suggest(String.upcase(query) <> ", ", "г. Тюмень")
    refute_received {:request, _, _}
  end

  test "is unavailable until enabled" do
    assert {:error, :dadata_not_configured} = Dadata.suggest("ленина", nil)

    configure(%{enabled: false})
    refute Dadata.active?()
    assert {:error, :dadata_not_configured} = Dadata.geolocate(57.1, 65.5)
  end

  test "parallel identical requests make one API call" do
    configure()
    query = "ленина #{System.unique_integer([:positive])}"
    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      send(test_pid, :called)
      Process.sleep(100)
      Req.Test.json(conn, %{"suggestions" => [suggestion("ул Ленина", "1")]})
    end)

    results =
      1..5
      |> Enum.map(fn _ -> Task.async(fn -> Dadata.suggest(query, nil) end) end)
      |> Task.await_many()

    assert Enum.all?(results, &match?({:ok, [_]}, &1))
    assert_received :called
    refute_received :called
  end

  test "a quota error returns no suggestions and pauses the API for a while" do
    configure()
    on_exit(fn -> Cachex.del(:geo_cache, :unavailable) end)
    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      send(test_pid, :called)
      conn |> Plug.Conn.put_status(429) |> Req.Test.json(%{"message" => "limit"})
    end)

    first = "квота #{System.unique_integer([:positive])}"
    assert {:ok, []} = Dadata.suggest(first, nil)
    assert_received :called

    assert {:ok, []} = Dadata.suggest("другая #{System.unique_integer([:positive])}", nil)
    refute_received :called

    Cachex.del(:geo_cache, :unavailable)
    assert {:ok, []} = Dadata.suggest(first, nil)
    assert_received :called
  end
end
