defmodule Delivest.Integrations.DadataTest do
  use Delivest.DataCase, async: true

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
        "geo_lon" => "65.534"
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
        longitude: 65.534
      }
    ]

    assert {:ok, ^expected} = Dadata.suggest(query, "г. Тюмень")
    assert_received {:request, ["Token key"], %{"locations" => [%{"city" => "Тюмень"}]}}

    assert {:ok, ^expected} = Dadata.suggest(query, "г. Тюмень")
    refute_received {:request, _, _}
  end

  test "is unavailable until enabled" do
    assert {:error, :dadata_not_configured} = Dadata.suggest("ленина", nil)

    configure(%{enabled: false})
    refute Dadata.active?()
    assert {:error, :dadata_not_configured} = Dadata.geolocate(57.1, 65.5)
  end
end
