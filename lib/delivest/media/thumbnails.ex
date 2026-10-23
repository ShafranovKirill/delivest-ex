defmodule Delivest.Media.Thumbnails do
  import Ecto.Query

  alias Delivest.Media.{File, Thumbnail}
  alias Delivest.Media.Workers.ThumbnailWorker
  alias Delivest.Repo

  def enqueue(%File{is_private: false, thumb_key: nil} = file),
    do: %{file_id: file.id} |> ThumbnailWorker.new() |> Oban.insert()

  def enqueue(_file), do: :ok

  def enqueue_missing do
    File
    |> where([f], not f.is_private and is_nil(f.thumb_key))
    |> Repo.all()
    |> Enum.each(&enqueue/1)
  end

  def store(%File{} = file) do
    key = Thumbnail.key(file.key)

    with {:ok, %{body: original}} <- request(ExAws.S3.get_object(file.bucket, file.key)),
         {:ok, webp} <- Thumbnail.build(original, file.context),
         {:ok, _response} <- request(put_object(file.bucket, key, webp)) do
      file |> File.thumb_changeset(key) |> Repo.update()
    end
  end

  def delete(%File{thumb_key: nil}), do: :ok

  def delete(%File{} = file) do
    with {:ok, _response} <- request(ExAws.S3.delete_object(file.bucket, file.thumb_key)),
         do: :ok
  end

  defp put_object(bucket, key, body),
    do: ExAws.S3.put_object(bucket, key, body, content_type: "image/webp")

  defp request(operation), do: ExAws.request(operation)
end
