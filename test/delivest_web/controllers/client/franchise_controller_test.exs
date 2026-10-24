defmodule DelivestWeb.Client.FranchiseControllerTest do
  use DelivestWeb.ConnCase, async: false

  import Delivest.Factory

  setup do
    Cachex.clear(:franchise_cache)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))

    {:ok, _} =
      Delivest.Franchise.update_settings(admin, %{
        "name" => "Sushi Like",
        "primary_color" => "#123456",
        "legal_form" => "ООО",
        "legal_name" => "Суши"
      })

    :ok
  end

  test "returns the franchise settings", %{conn: conn} do
    assert %{
             "name" => "Sushi Like",
             "primary_color" => "#123456",
             "logo_url" => nil,
             "logo_dark_url" => nil,
             "legal" => %{"form" => "ООО", "name" => "Суши"},
             "documents" => [%{"kind" => "privacy"} | _]
           } = conn |> get(~p"/client/franchise") |> json_response(200) |> Map.fetch!("data")
  end

  test "returns logo urls once uploaded", %{conn: conn} do
    Delivest.S3Stub.record(self())
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    {:ok, _} = Delivest.Franchise.update_logo(admin, :light, Delivest.S3Stub.png(400, 100))

    assert %{"logo_url" => url, "logo_dark_url" => nil} =
             conn |> get(~p"/client/franchise") |> json_response(200) |> Map.fetch!("data")

    assert url =~ ~r{/franchise/logo/.+\.png$}
  end

  test "returns a rendered document", %{conn: conn} do
    assert %{"kind" => "offer", "body" => body} =
             conn
             |> get(~p"/client/franchise/documents/offer")
             |> json_response(200)
             |> Map.fetch!("data")

    assert body =~ "ООО Суши"
  end

  test "unknown document is not found", %{conn: conn} do
    assert %{"error" => "document_not_found"} =
             conn |> get(~p"/client/franchise/documents/nope") |> json_response(404)
  end
end
