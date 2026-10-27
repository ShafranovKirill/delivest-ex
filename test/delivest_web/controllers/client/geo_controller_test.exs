defmodule DelivestWeb.Client.GeoControllerTest do
  use DelivestWeb.ConnCase, async: true

  alias Delivest.Integrations.Dadata.Settings
  alias Delivest.Repo

  defp configure, do: Repo.insert!(%Settings{api_key: "key", enabled: true})

  test "suggests addresses", %{conn: conn} do
    configure()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{
        "suggestions" => [
          %{
            "value" => "ул Ленина, д 1",
            "data" => %{"street_with_type" => "ул Ленина", "house" => "1"}
          }
        ]
      })
    end)

    query = "ленина #{System.unique_integer([:positive])}"

    assert [%{"street" => "ул Ленина", "house" => "1", "latitude" => nil}] =
             conn
             |> get(~p"/client/geo/suggest", %{query: query, city: "Тюмень"})
             |> json_response(200)
             |> Map.fetch!("data")
  end

  test "a short query gives nothing", %{conn: conn} do
    assert %{"data" => []} =
             conn |> get(~p"/client/geo/suggest", %{query: " ле "}) |> json_response(200)
  end

  test "finds the house by coordinates", %{conn: conn} do
    configure()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{
        "suggestions" => [
          %{
            "value" => "г Тюмень, ул Ленина, д 2",
            "data" => %{"city" => "Тюмень", "street_with_type" => "ул Ленина", "house" => "2"}
          }
        ]
      })
    end)

    assert [%{"city" => "Тюмень", "house" => "2"}] =
             conn
             |> get(~p"/client/geo/reverse", %{latitude: "57.11111", longitude: "65.22222"})
             |> json_response(200)
             |> Map.fetch!("data")
  end

  test "rejects broken coordinates", %{conn: conn} do
    assert %{"error" => "invalid_coordinates"} =
             conn
             |> get(~p"/client/geo/reverse", %{latitude: "95", longitude: "65"})
             |> json_response(422)
  end

  test "reports disabled suggestions", %{conn: conn} do
    assert %{"error" => "address_suggestions_disabled"} =
             conn |> get(~p"/client/geo/suggest", %{query: "ленина"}) |> json_response(503)
  end
end
