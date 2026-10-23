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

  test "an unreadable image is cancelled instead of retried" do
    serve_image("not an image")
    file = create_file()

    assert {:cancel, :invalid_image} = perform_job(ThumbnailWorker, %{file_id: file.id})
    assert Repo.reload!(file).thumb_key == nil
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
