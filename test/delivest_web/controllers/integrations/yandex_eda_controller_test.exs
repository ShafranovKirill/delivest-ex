defmodule DelivestWeb.Integrations.YandexEdaControllerTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.YandexEdaFixtures

  alias Delivest.Integrations.YandexEda
  alias Delivest.Net.ProductStop
  alias Delivest.Repo

  @base "/integrations/yandex-eda"

  setup %{conn: conn} do
    settings = credentials()
    {:ok, token} = YandexEda.issue_token(settings.client_id, settings.client_secret)
    branch = yandex_branch()
    product = menu_product(branch, menu_category(branch), name: "Борщ", price: 300)

    %{
      conn: put_req_header(conn, "authorization", "Bearer " <> token),
      anonymous: conn,
      settings: settings,
      branch: branch,
      product: product
    }
  end

  describe "token" do
    test "client credentials get a bearer token", %{anonymous: conn, settings: settings} do
      body =
        conn
        |> post(@base <> "/security/oauth/token", %{
          "client_id" => settings.client_id,
          "client_secret" => settings.client_secret,
          "grant_type" => "client_credentials"
        })
        |> json_response(200)

      assert %{"token_type" => "bearer", "expires_in" => 86_400, "access_token" => token} = body
      assert YandexEda.valid_token?(token)
    end

    test "wrong credentials get an error list", %{anonymous: conn, settings: settings} do
      assert [%{"code" => 101}] =
               conn
               |> post(@base <> "/security/oauth/token", %{
                 "client_id" => settings.client_id,
                 "client_secret" => "wrong",
                 "grant_type" => "client_credentials"
               })
               |> json_response(400)

      assert [%{"code" => 100}] =
               conn |> post(@base <> "/security/oauth/token", %{}) |> json_response(400)
    end

    test "requests without a valid token are unauthorized", %{anonymous: conn} do
      assert %{"reason" => _} = conn |> get(@base <> "/restaurants") |> json_response(401)

      assert %{"reason" => _} =
               conn
               |> put_req_header("authorization", "Bearer broken")
               |> get(@base <> "/restaurants")
               |> json_response(401)
    end
  end

  describe "restaurants and menu" do
    test "restaurants, availability and schedule", %{conn: conn, branch: branch} do
      assert %{"places" => [%{"id" => id}]} =
               conn |> get(@base <> "/restaurants") |> json_response(200)

      assert id == branch.id

      assert %{"places" => [%{"enabled" => true}]} =
               conn |> get(@base <> "/restaurants/availability") |> json_response(200)

      assert %{"mon" => []} =
               conn |> get(@base <> "/places/#{branch.id}/schedule") |> json_response(200)
    end

    test "the menu is typed", %{conn: conn, branch: branch, product: product} do
      conn = get(conn, @base <> "/menu/#{branch.id}/composition")

      assert response_content_type(conn, :json) =~
               "application/vnd.eats.menu.composition.v2+json"

      assert %{"items" => [%{"id" => id, "price" => 300}]} = Jason.decode!(conn.resp_body)
      assert id == product.id
    end

    test "the stop list is typed", %{conn: conn, branch: branch, product: product} do
      Repo.insert!(%ProductStop{
        branch_id: branch.id,
        product_id: product.id,
        source: ProductStop.manual()
      })

      Cachex.del(:stop_cache, branch.id)
      conn = get(conn, @base <> "/menu/#{branch.id}/availability")

      assert response_content_type(conn, :json) =~
               "application/vnd.eats.menu.availability.v2+json"

      assert %{"items" => [%{"stock" => 0}]} = Jason.decode!(conn.resp_body)
    end

    test "an unknown restaurant is 404", %{conn: conn} do
      assert [%{"code" => 102}] =
               conn
               |> get(@base <> "/menu/#{Ecto.UUID.generate()}/composition")
               |> json_response(404)
    end
  end

  describe "orders" do
    test "the full order flow", %{conn: conn, branch: branch, product: product} do
      params = order_params(branch, [product])

      assert %{"result" => "OK", "orderId" => order_id} =
               conn |> post(@base <> "/order", params) |> json_response(200)

      assert %{"orderId" => ^order_id} =
               conn |> post(@base <> "/order", params) |> json_response(200)

      shown = get(conn, @base <> "/order/#{order_id}")
      assert response_content_type(shown, :json) =~ "application/vnd.eats.order.v2+json"
      assert %{"eatsId" => eats_id} = Jason.decode!(shown.resp_body)
      assert eats_id == params["eatsId"]

      assert %{"status" => "ACCEPTED_BY_RESTAURANT"} =
               conn |> get(@base <> "/order/#{order_id}/status") |> json_response(200)

      assert conn
             |> put(@base <> "/order/#{order_id}/courier", %{"courier" => %{"name" => "Иван"}})
             |> response(204)

      assert conn
             |> put(@base <> "/order/#{order_id}/status", %{"status" => "TAKEN_BY_COURIER"})
             |> response(204)

      assert [%{"code" => 100}] =
               conn
               |> put(@base <> "/order/#{order_id}/status", %{"status" => "COOKING"})
               |> json_response(400)

      assert [%{"code" => 105}] =
               conn |> put(@base <> "/order/#{order_id}", %{}) |> json_response(422)

      assert conn
             |> delete(@base <> "/order/#{order_id}", %{"comment" => "Отмена"})
             |> response(200)

      assert %{"status" => "CANCELLED"} =
               conn |> get(@base <> "/order/#{order_id}/status") |> json_response(200)
    end

    test "unavailable goods are 406", %{conn: conn, branch: branch, product: product} do
      Repo.insert!(%ProductStop{
        branch_id: branch.id,
        product_id: product.id,
        source: ProductStop.manual()
      })

      Cachex.del(:stop_cache, branch.id)

      body =
        conn |> post(@base <> "/order", order_params(branch, [product])) |> json_response(406)

      assert %{"type" => "unavailable_goods", "goods" => goods, "message" => message} = body
      assert goods == %{product.id => "Борщ"}
      assert message =~ "Борщ"
    end

    test "a broken order is 400", %{conn: conn, branch: branch, product: product} do
      params = branch |> order_params([product]) |> Map.delete("eatsId")

      assert [%{"code" => 100, "description" => "eatsId is required"}] =
               conn |> post(@base <> "/order", params) |> json_response(400)
    end

    test "an unknown order is 404", %{conn: conn} do
      assert [%{"code" => 103}] =
               conn |> get(@base <> "/order/#{Ecto.UUID.generate()}/status") |> json_response(404)
    end
  end

  describe "feedback" do
    test "a review is saved on the order", %{conn: conn, branch: branch, product: product} do
      params = order_params(branch, [product])
      {:ok, order} = YandexEda.create_order(params)

      feedback = %{
        "id" => "f1",
        "eatsId" => params["eatsId"],
        "restaurantId" => branch.id,
        "rating" => 4,
        "comment" => "Остыло",
        "predefinedComment" => "Долго",
        "createdAt" => "2026-10-27T13:00:00.000000+03:00"
      }

      assert %{"result" => "OK"} =
               conn
               |> post(@base <> "/v1/feedback", %{"feedback" => feedback})
               |> json_response(200)

      assert {:ok, %{channel: %{details: %{"feedback" => saved}}}} =
               YandexEda.get_order(order.id)

      assert %{"rating" => 4, "comment" => "Остыло", "predefined_comment" => "Долго"} = saved

      assert %{"result" => "OK"} =
               conn
               |> post(@base <> "/v1/feedback", %{
                 "feedback" => Map.put(feedback, "orderId", order.id)
               })
               |> json_response(200)
    end

    test "a review of an unknown order is 404 and a broken one is 400", %{conn: conn} do
      feedback = %{"orderId" => Ecto.UUID.generate(), "eatsId" => "nope", "rating" => 5}

      assert [%{"code" => 103}] =
               conn
               |> post(@base <> "/v1/feedback", %{"feedback" => feedback})
               |> json_response(404)

      assert [%{"code" => 100}] =
               conn
               |> post(@base <> "/v1/feedback", %{"feedback" => %{feedback | "rating" => 7}})
               |> json_response(400)
    end
  end
end
