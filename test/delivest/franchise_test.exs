defmodule Delivest.FranchiseTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory

  alias Delivest.Franchise

  setup do
    Cachex.clear(:franchise_cache)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    manager = insert(:staff, role: insert(:role, permissions: ["branches.update"]))
    %{admin: admin, manager: manager}
  end

  test "returns defaults until settings are saved" do
    assert %{name: "Delivest", primary_color: "#48010c"} = Franchise.get_settings()
  end

  test "only an admin updates settings and the cache follows", %{admin: admin, manager: manager} do
    assert {:error, :forbidden} = Franchise.update_settings(manager, %{"name" => "Pizza"})

    assert {:ok, _} =
             Franchise.update_settings(admin, %{"name" => "Pizza", "primary_color" => "#FF0000"})

    assert %{name: "Pizza", primary_color: "#ff0000"} = Franchise.get_settings()
  end

  test "validates color and requisites", %{admin: admin} do
    assert {:error, changeset} =
             Franchise.update_settings(admin, %{
               "primary_color" => "red",
               "inn" => "123",
               "ogrn" => "1"
             })

    assert %{primary_color: _, inn: _, ogrn: _} = errors_on(changeset)
  end

  test "documents use templates with requisites until edited", %{admin: admin} do
    {:ok, _} = Franchise.update_settings(admin, %{"legal_name" => "Вкус", "inn" => "7700000000"})

    assert %{custom: false, body: body} = Franchise.get_document(:privacy)
    assert body =~ "Вкус"
    assert body =~ "7700000000"
    refute body =~ "{{"

    {:ok, _} = Franchise.update_document(admin, :privacy, "Своя политика {{brand}} {{unknown}}")

    assert %{custom: true, body: "Своя политика Delivest {{unknown}}"} =
             Franchise.get_document(:privacy)

    {:ok, _} = Franchise.reset_document(admin, :privacy)
    assert %{custom: false} = Franchise.get_document(:privacy)
  end

  describe "images" do
    setup do
      Delivest.S3Stub.record(self())
      :ok
    end

    test "an icon is cut into favicon sizes and replaces the previous one", %{admin: admin} do
      assert {:ok, %{icon_key: "franchise/icon/" <> _ = dir}} =
               Franchise.update_icon(admin, Delivest.S3Stub.png(600, 400))

      for name <- ~w(favicon.ico icon-32.png apple-touch-icon.png icon-192.png icon-512.png) do
        assert_received {:s3, "PUT", "/delivest/" <> key, _body}
        assert key == "#{dir}/#{name}"
      end

      assert %{icon_key: ^dir} = Franchise.get_settings()

      assert {:ok, %{icon_key: nil}} = Franchise.remove_icon(admin)
      assert_received {:s3, "DELETE", "/delivest/" <> deleted, ""}
      assert deleted == "#{dir}/favicon.ico"
    end

    test "the link preview is cropped to 1200 by 630", %{admin: admin} do
      assert {:ok, %{share_image_key: key}} =
               Franchise.update_share_image(admin, Delivest.S3Stub.png(1600, 1600))

      assert_received {:s3, "PUT", "/delivest/" <> ^key, jpeg}
      {:ok, image} = Vix.Vips.Image.new_from_buffer(jpeg)
      assert {1200, 630} == {Vix.Vips.Image.width(image), Vix.Vips.Image.height(image)}
    end

    test "a logo keeps its proportions and is never upscaled", %{admin: admin} do
      assert {:ok, %{logo_key: "franchise/logo/" <> _ = key}} =
               Franchise.update_logo(admin, :light, Delivest.S3Stub.png(1200, 300))

      assert_received {:s3, "PUT", "/delivest/" <> ^key, png}
      assert {640, 160} == size(png)

      assert {:ok, %{logo_dark_key: dark_key, logo_key: ^key}} =
               Franchise.update_logo(admin, :dark, Delivest.S3Stub.png(300, 80))

      assert_received {:s3, "PUT", "/delivest/" <> ^dark_key, dark_png}
      assert {300, 80} == size(dark_png)
    end

    test "a new logo replaces the previous one", %{admin: admin} do
      {:ok, %{logo_key: first}} =
        Franchise.update_logo(admin, :light, Delivest.S3Stub.png(400, 100))

      {:ok, %{logo_key: second}} =
        Franchise.update_logo(admin, :light, Delivest.S3Stub.png(400, 100))

      assert_received {:s3, "DELETE", "/delivest/" <> ^first, ""}

      assert {:ok, %{logo_key: nil}} = Franchise.remove_logo(admin, :light)
      assert_received {:s3, "DELETE", "/delivest/" <> ^second, ""}
    end

    test "rejects small and broken images and non admins", %{admin: admin, manager: manager} do
      assert {:error, :too_small} = Franchise.update_icon(admin, Delivest.S3Stub.png(64, 64))

      assert {:error, :too_small} =
               Franchise.update_logo(admin, :light, Delivest.S3Stub.png(400, 20))

      assert {:error, :forbidden} = Franchise.remove_logo(manager, :dark)

      assert {:error, :too_small} =
               Franchise.update_share_image(admin, Delivest.S3Stub.png(300, 200))

      assert {:error, :invalid_image} = Franchise.update_icon(admin, "not an image")
      assert {:error, :forbidden} = Franchise.update_icon(manager, Delivest.S3Stub.png(600, 600))
      refute_received {:s3, _method, _path, _body}
    end
  end

  defp size(binary) do
    {:ok, image} = Vix.Vips.Image.new_from_buffer(binary)
    {Vix.Vips.Image.width(image), Vix.Vips.Image.height(image)}
  end
end
