defmodule Delivest.PublicSiteTest do
  use ExUnit.Case, async: false

  alias Delivest.PublicSite
  alias DelivestWeb.Endpoint
  alias DelivestWeb.Seo.SeoSite

  defmodule CorsAdapter do
    def put(config) do
      send(self(), {:cors, config})
      if Process.get(:fail_cors), do: {:error, :s3_down}, else: :ok
    end
  end

  setup do
    path = Path.join(System.tmp_dir!(), "public-site-#{System.unique_integer([:positive])}.json")
    old_path = Application.get_env(:delivest, :public_site_config_path)
    old_adapter = Application.get_env(:delivest, :public_site_cors_adapter)
    Application.put_env(:delivest, :public_site_config_path, path)
    Application.put_env(:delivest, :public_site_cors_adapter, CorsAdapter)

    on_exit(fn ->
      Application.put_env(:delivest, :public_site_config_path, old_path)
      Application.put_env(:delivest, :public_site_cors_adapter, old_adapter)
      File.rm(path)
    end)

    %{path: path}
  end

  test "new storefront origin is allowed before switching primary and persists", %{path: path} do
    old = PublicSite.primary_url()
    new = "https://new.example.org"
    assert {:ok, _} = PublicSite.apply(%{"primary_url" => old, "origins" => [old, new]})
    assert_receive {:cors, %{"origins" => [^old, ^new]}}
    assert PublicSite.current()["primary_url"] == old
    assert Endpoint.fetch_cors_origin(nil) == [old, new]
    assert Endpoint.allowed_socket_origin?(URI.parse(new))
    assert SeoSite.origin() == old
    assert File.exists?(path)

    assert {:ok, _} = PublicSite.apply(%{"primary_url" => new, "origins" => [old, new]})
    assert SeoSite.origin() == new
    assert PublicSite.current()["primary_url"] == new
    assert {:ok, _} = PublicSite.apply(%{"primary_url" => old, "origins" => [old, new]})
    assert SeoSite.origin() == old
  end

  test "invalid URL or S3 CORS failure retains old canonical address", %{path: path} do
    old = PublicSite.current()

    assert {:error, :invalid_origin} =
             PublicSite.apply(%{
               "primary_url" => "https://other.example.org/path",
               "origins" => ["https://other.example.org/path"]
             })

    Process.put(:fail_cors, true)

    assert {:error, _} =
             PublicSite.apply(%{
               "primary_url" => "https://other.example.org",
               "origins" => ["https://other.example.org"]
             })

    assert PublicSite.current() == old
    refute File.exists?(path)
  end

  test "corrupt saved config fails closed on boot and read", %{path: path} do
    File.write!(path, "not-json")
    assert_raise RuntimeError, ~r/invalid public-site configuration/, &PublicSite.current/0
    assert_raise RuntimeError, ~r/invalid public-site configuration/, &PublicSite.validate_boot!/0
  end

  test "managed RPC emits JSON and rejects an insecure production origin" do
    old_env = Application.get_env(:delivest, :env)
    Application.put_env(:delivest, :env, :prod)
    on_exit(fn -> Application.put_env(:delivest, :env, old_env) end)

    config = %{
      "primary_url" => "http://insecure.example.org",
      "origins" => ["http://insecure.example.org"]
    }

    assert {:error, :invalid_origin} = PublicSite.apply(config)

    assert_raise RuntimeError, ~r/public-site update failed/, fn ->
      PublicSite.apply_encoded(Base.encode64(Jason.encode!(config)))
    end

    assert Jason.decode!(ExUnit.CaptureIO.capture_io(&PublicSite.current_json/0)) ==
             PublicSite.current()
  end

  test "S3 CORS accepts prepared and API origins through its internal endpoint" do
    Req.Test.stub(Delivest.S3Stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(self(), {:cors_request, conn.request_path, body})
      Plug.Conn.send_resp(conn, 200, "")
    end)

    assert :ok =
             PublicSite.put(%{
               "primary_url" => "https://old.example.org",
               "origins" => ["https://old.example.org", "https://new.example.org"]
             })

    assert_received {:cors_request, _, body}
    assert String.contains?(body, "https://new.example.org")
  end
end
