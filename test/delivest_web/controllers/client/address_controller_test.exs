defmodule DelivestWeb.Client.AddressControllerTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  alias DelivestWeb.ClientToken

  defp authed(client) do
    put_req_header(
      build_conn(),
      "authorization",
      "Bearer " <> ClientToken.issue(client.id).access_token
    )
  end

  test "client manages own addresses only" do
    client = insert(:client)
    stranger = insert(:client)

    created =
      client
      |> authed()
      |> post(~p"/client/addresses", %{street: "Ленина", house: "10"})
      |> json_response(200)
      |> Map.fetch!("data")

    assert [%{"street" => "Ленина"}] =
             client
             |> authed()
             |> get(~p"/client/addresses")
             |> json_response(200)
             |> Map.fetch!("data")

    assert [] =
             stranger
             |> authed()
             |> get(~p"/client/addresses")
             |> json_response(200)
             |> Map.fetch!("data")

    assert %{"error" => "address_not_found"} =
             stranger
             |> authed()
             |> put(~p"/client/addresses/#{created["id"]}", %{street: "X"})
             |> json_response(404)

    assert %{"data" => %{"apartment" => "5"}} =
             client
             |> authed()
             |> put(~p"/client/addresses/#{created["id"]}", %{apartment: "5"})
             |> json_response(200)

    assert %{"error" => "validation_failed"} =
             client
             |> authed()
             |> put(~p"/client/addresses/#{created["id"]}", %{street: ""})
             |> json_response(422)

    assert client |> authed() |> delete(~p"/client/addresses/#{created["id"]}") |> response(204)

    assert [] =
             client
             |> authed()
             |> get(~p"/client/addresses")
             |> json_response(200)
             |> Map.fetch!("data")
  end
end
