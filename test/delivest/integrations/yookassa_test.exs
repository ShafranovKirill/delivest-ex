defmodule Delivest.Integrations.YookassaTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Integrations.{Health, Yookassa}
  alias Delivest.Integrations.Yookassa.Settings

  defp configure, do: Repo.insert!(%Settings{shop_id: "506751", secret_key: "live_secret"})

  defp me(body), do: Req.Test.stub(Delivest.HTTP.Client, fn conn -> Req.Test.json(conn, body) end)

  describe "settings" do
    test "the form needs a numeric shop id and a key, and makes a webhook token" do
      assert {:error, changeset} = Yookassa.update_settings(admin(), %{shop_id: "abc"})
      assert %{shop_id: [_], secret_key: ["can't be blank"]} = errors_on(changeset)

      assert {:ok, settings} =
               Yookassa.update_settings(admin(), %{shop_id: " 506751 ", secret_key: "live_x"})

      assert settings.shop_id == "506751"
      assert byte_size(settings.webhook_token) >= 24
      assert Yookassa.configured?()
    end

    test "an empty key keeps the saved one and the token stays" do
      settings = configure()

      assert {:ok, saved} =
               Yookassa.update_settings(admin(), %{shop_id: "506751", secret_key: ""})

      assert saved.secret_key == "live_secret"
      assert saved.id == settings.id
      assert saved.webhook_token != nil
    end

    test "only an admin changes the shop" do
      staff = insert(:staff, role: insert(:role, permissions: ["orders.read"]))

      assert {:error, :forbidden} =
               Yookassa.update_settings(staff, %{shop_id: "1", secret_key: "k"})
    end

    test "the webhook token is compared in constant time against the saved one" do
      {:ok, settings} = Yookassa.update_settings(admin(), %{shop_id: "1", secret_key: "k"})

      assert Yookassa.valid_webhook_token?(settings.webhook_token)
      refute Yookassa.valid_webhook_token?("other")
      refute Yookassa.valid_webhook_token?(nil)
    end
  end

  describe "connection check" do
    test "needs complete settings" do
      assert {:error, :yookassa_not_configured} = Yookassa.health_check(%Settings{})
    end

    test "records ok, and a rejected key as auth" do
      configure()
      me(%{"account_id" => "506751", "status" => "enabled", "test" => true})
      assert {:ok, %{status: :ok}} = Health.check(:yookassa, nil)

      Req.Test.stub(Delivest.HTTP.Client, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"type" => "error"})
      end)

      assert {:ok, %{status: :auth}} = Health.check(:yookassa, nil)
    end

    test "sends the shop as basic auth" do
      settings = configure()

      Req.Test.stub(Delivest.HTTP.Client, fn conn ->
        assert ["Basic " <> encoded] = Plug.Conn.get_req_header(conn, "authorization")
        assert Base.decode64!(encoded) == "506751:live_secret"
        Req.Test.json(conn, %{"account_id" => "506751"})
      end)

      assert :ok = Yookassa.health_check(settings)
    end
  end

  describe "shop" do
    test "reads the fiscalization the shop already has" do
      settings = configure()

      me(%{
        "account_id" => "506751",
        "status" => "enabled",
        "test" => false,
        "fiscalization" => %{"enabled" => true, "provider" => "atol"}
      })

      assert {:ok, %{receipts_conflict: true, fiscalization: "atol", enabled: true, test: false}} =
               Yookassa.shop(settings)
    end

    test "a shop without fiscalization has no conflict with our receipts" do
      settings = configure()
      me(%{"account_id" => "506751", "status" => "enabled", "test" => true})

      assert {:ok, %{receipts_conflict: false, fiscalization: nil, test: true}} =
               Yookassa.shop(settings)
    end
  end

  defp admin, do: insert(:staff, role: insert(:role, permissions: ["admin"]))
end
