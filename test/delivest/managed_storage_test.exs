defmodule Delivest.ManagedStorageTest do
  use ExUnit.Case, async: false

  alias Delivest.ManagedStorage

  defmodule HttpProbe do
    def request(options) do
      url = Keyword.fetch!(options, :url)
      method = Keyword.fetch!(options, :method)
      uri = URI.parse(url)
      send(self(), {:public_request, method, uri.host, uri.path, uri.query})

      cond do
        method == :put ->
          {:ok, %{status: 200, body: ""}}

        String.contains?(uri.path, "delivest-private") and is_nil(uri.query) ->
          {:ok, %{status: 403, body: "denied"}}

        String.contains?(uri.path, "delivest-private") ->
          {:ok, %{status: 200, body: "delivest-storage-probe"}}

        true ->
          {:ok, %{status: 200, body: "delivest-public-upload-probe"}}
      end
    end
  end

  defmodule BadHttpProbe do
    def request(options) do
      url = URI.parse(Keyword.fetch!(options, :url))

      if String.contains?(url.path, "delivest-private") and is_nil(url.query),
        do: {:ok, %{status: 403, body: "denied"}},
        else: {:ok, %{status: 200, body: "wrong data"}}
    end
  end

  setup do
    old_media = Application.get_env(:delivest, Delivest.Media)
    old_adapter = Application.get_env(:delivest, :managed_storage_http_adapter)

    Application.put_env(
      :delivest,
      Delivest.Media,
      old_media
      |> Keyword.put(:public_host, "media.example.org")
      |> Keyword.put(:public_scheme, "https://")
      |> Keyword.put(:public_port, 443)
    )

    Application.put_env(:delivest, :managed_storage_http_adapter, HttpProbe)

    Req.Test.stub(Delivest.S3Stub, fn conn -> Plug.Conn.send_resp(conn, 200, "") end)

    on_exit(fn ->
      Application.put_env(:delivest, Delivest.Media, old_media)
      Application.put_env(:delivest, :managed_storage_http_adapter, old_adapter)
    end)

    :ok
  end

  test "checks real internal operations and public signed and anonymous routes" do
    assert %{
             "public_upload" => true,
             "public_read" => true,
             "private_signed" => true,
             "internal_endpoint" => true
           } = ManagedStorage.run!()

    assert_received {:public_request, :put, "media.example.org", _, _}
    assert_received {:public_request, :get, "media.example.org", _, _}
  end

  test "matching HTTP status with wrong object body fails readiness" do
    Application.put_env(:delivest, :managed_storage_http_adapter, BadHttpProbe)
    assert_raise RuntimeError, ~r/public media check failed/, &ManagedStorage.run!/0
  end

  test "managed bootstrap rejects missing stable admin password before migration" do
    old = System.get_env("ADMIN_PASSWORD")
    System.delete_env("ADMIN_PASSWORD")

    on_exit(fn ->
      if old, do: System.put_env("ADMIN_PASSWORD", old), else: System.delete_env("ADMIN_PASSWORD")
    end)

    assert_raise RuntimeError,
                 ~r/managed admin password is missing/,
                 &Delivest.Release.setup_managed/0
  end
end
