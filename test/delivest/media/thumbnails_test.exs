defmodule Delivest.Media.ThumbnailsTest do
  use Delivest.DataCase, async: true
  use Oban.Testing, repo: Delivest.Repo

  alias Delivest.{Media, S3Stub}
  alias Delivest.Media.{File, Thumbnail, Thumbnails}
  alias Delivest.Media.Workers.ThumbnailWorker

  defp create_file(attrs \\ %{}) do
    {:ok, file} =
      %{
        "bucket" => "delivest",
        "key" => "product/menu/pizza.png",
        "original_name" => "pizza.png",
        "mime_type" => "image/png",
        "size" => 1,
        "context" => "product",
        "is_private" => false,
        "owner_id" => Ecto.UUID.generate()
      }
      |> Map.merge(attrs)
      |> Media.create_file()

    file
  end

  defp serve_image(png) do
    test_pid = self()

    Req.Test.stub(S3Stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn, length: 20_000_000)
      send(test_pid, {:s3, conn.method, conn.request_path, body})
      Plug.Conn.send_resp(conn, 200, if(conn.method == "GET", do: png, else: ""))
    end)
  end

  test "a public upload queues its thumbnail" do
    file = create_file()
    assert_enqueued(worker: ThumbnailWorker, args: %{file_id: file.id})
  end

  test "a private upload gets no thumbnail" do
    create_file(%{"is_private" => true})
    refute_enqueued(worker: ThumbnailWorker)
  end

  test "the thumbnail is a downscaled webp next to the original" do
    serve_image(S3Stub.png(2000, 1000))
    file = create_file()

    assert :ok = perform_job(ThumbnailWorker, %{file_id: file.id})

    assert_received {:s3, "PUT", "/delivest/product/menu/pizza_thumb.webp", webp}
    {:ok, image} = Vix.Vips.Image.new_from_buffer(webp)
    assert Vix.Vips.Image.width(image) == 800
    assert Repo.reload!(file).thumb_key == "product/menu/pizza_thumb.webp"
  end

  test "product variants expose actual widths without upscaling small originals" do
    serve_image(S3Stub.png(300, 150))
    file = create_file()

    assert :ok = perform_job(ThumbnailWorker, %{file_id: file.id})
    updated = Repo.reload!(file)
    assert updated.thumb_key == Thumbnail.key(file.key)
    assert updated.variant_keys["192"]["width"] == 192
    assert updated.variant_keys["384"]["width"] == 300
    assert updated.variant_keys["800"]["width"] == 300
    assert Enum.map(Media.photo_variants_from_file(updated), & &1.width) == [192, 300]

    first_key = Thumbnail.variant_key(file.key, 192, S3Stub.png(300, 150))
    assert_received {:s3, "PUT", "/delivest/" <> ^first_key, first_webp}
    {:ok, image} = Vix.Vips.Image.new_from_buffer(first_webp)
    assert Vix.Vips.Image.width(image) == 192
  end

  test "retry builds missing variants without rewriting a successful thumbnail" do
    file = create_file()
    png = S3Stub.png(1000, 500)
    test_pid = self()

    Req.Test.stub(S3Stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn, length: 20_000_000)
      send(test_pid, {:s3, conn.method, conn.request_path, body})

      if conn.method == "PUT" and String.contains?(conn.request_path, "_v2_384_") do
        Plug.Conn.send_resp(conn, 500, "")
      else
        Plug.Conn.send_resp(conn, 200, if(conn.method == "GET", do: png, else: ""))
      end
    end)

    assert {:error, _} = perform_job(ThumbnailWorker, %{file_id: file.id})
    updated = Repo.reload!(file)
    assert updated.thumb_key == Thumbnail.key(file.key)
    assert updated.variant_keys["192"]["width"] == 192
    assert updated.variant_keys["384"] == nil
    assert_received {:s3, "PUT", "/delivest/product/menu/pizza_thumb.webp", _}
    assert_received {:s3, "PUT", "/delivest/product/menu/pizza_thumb_v2_192_" <> _, _}
    refute_received {:s3, "PUT", "/delivest/product/menu/pizza_thumb_v2_800_" <> _, _}

    serve_image(png)
    assert :ok = perform_job(ThumbnailWorker, %{file_id: file.id})
    assert Repo.reload!(file).variant_keys["384"]["width"] == 384
    refute_received {:s3, "PUT", "/delivest/product/menu/pizza_thumb.webp", _}
    refute_received {:s3, "PUT", "/delivest/product/menu/pizza_thumb_v2_192_" <> _, _}
  end

  test "variant keys include image content and deletion includes published variants" do
    assert Thumbnail.variant_key("product/a.png", 192, "first") !=
             Thumbnail.variant_key("product/a.png", 192, "second")

    file = create_file()
    serve_image(S3Stub.png(1200, 800))
    assert :ok = perform_job(ThumbnailWorker, %{file_id: file.id})

    assert {:ok, _} = Media.delete_file(Repo.reload!(file))
    assert_received {:s3, "DELETE", "/delivest/product/menu/pizza_thumb.webp", _}
    assert_received {:s3, "DELETE", "/delivest/product/menu/pizza_thumb_v2_192_" <> _, _}
    assert_received {:s3, "DELETE", "/delivest/product/menu/pizza_thumb_v2_384_" <> _, _}
    assert_received {:s3, "DELETE", "/delivest/product/menu/pizza.png", _}
  end

  test "transparent source keeps an alpha channel in WebP" do
    transparent_png =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg=="
      )

    assert {:ok, webp, 1} = Thumbnail.build_width(transparent_png, 192)
    assert {:ok, image} = Vix.Vips.Image.new_from_buffer(webp)
    assert Vix.Vips.Image.has_alpha?(image)
  end

  test "menu projection includes variants while preserving photo_url" do
    file = %File{
      bucket: "delivest",
      key: "product/a.png",
      context: :product,
      is_private: false,
      thumb_key: "product/a_thumb.webp",
      variant_keys: %{"192" => %{"key" => "product/a_thumb_v2_192.webp", "width" => 192}}
    }

    product = %{
      id: Ecto.UUID.generate(),
      name: "Pizza",
      price: 1_000,
      media: file,
      tags: []
    }

    projection = Delivest.Net.MenuView.build_product(product)
    assert projection.photo_url =~ "/delivest/product/a_thumb.webp"
    assert [%{url: url, width: 192}] = projection.photo_variants
    assert url =~ "/delivest/product/a_thumb_v2_192.webp"
  end

  test "an unreadable image is cancelled instead of retried" do
    serve_image("not an image")
    file = create_file()

    assert {:cancel, :invalid_image} = perform_job(ThumbnailWorker, %{file_id: file.id})
    assert Repo.reload!(file).thumb_key == nil
  end

  test "thumbnail deletion failure retains original and database row for retry" do
    file =
      create_file() |> File.thumb_changeset("product/menu/pizza_thumb.webp") |> Repo.update!()

    test_pid = self()

    Req.Test.stub(S3Stub, fn conn ->
      send(test_pid, {:delete, conn.request_path})
      Plug.Conn.send_resp(conn, 500, "")
    end)

    assert {:error, _} = Media.delete_file(file)
    assert_received {:delete, "/delivest/product/menu/pizza_thumb.webp"}
    refute_received {:delete, "/delivest/product/menu/pizza.png"}
    assert Repo.get!(File, file.id)

    S3Stub.record(self())
    assert {:ok, _} = Media.delete_file(file)
    assert_received {:s3, "DELETE", "/delivest/product/menu/pizza_thumb.webp", _}
    assert_received {:s3, "DELETE", "/delivest/product/menu/pizza.png", _}
    assert Repo.get(File, file.id) == nil
  end

  test "the thumbnail url falls back to the original until it is ready" do
    file = %File{bucket: "delivest", key: "product/a.png", is_private: false}

    assert Media.thumb_url_from_file(file) =~ "/delivest/product/a.png"

    assert Media.thumb_url_from_file(%{file | thumb_key: Thumbnail.key(file.key)}) =~
             "/delivest/product/a_thumb.webp"
  end

  test "missing thumbnails are queued once" do
    file = create_file()
    Thumbnails.enqueue_missing()

    assert [%{args: %{"file_id" => id}}] = all_enqueued(worker: ThumbnailWorker)
    assert id == file.id
  end
end
