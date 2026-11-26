defmodule Delivest.Media.Thumbnails do
  import Ecto.Query

  alias Delivest.Media.{File, Thumbnail}
  alias Delivest.Media.Workers.ThumbnailWorker
  alias Delivest.Net.{Catalogs, Product, SharedOwnership}
  alias Delivest.Repo

  def missing?(%File{is_private: true}), do: false
  def missing?(%File{thumb_key: nil}), do: true

  def missing?(%File{context: :product, variant_keys: variants}) do
    Enum.any?(Thumbnail.product_variants(), &(not valid_variant?(variants, &1)))
  end

  def missing?(_file), do: false

  def enqueue(%File{} = file) do
    if missing?(file),
      do: %{file_id: file.id} |> ThumbnailWorker.new() |> Oban.insert(),
      else: :ok
  end

  def enqueue_missing do
    enqueue_batch(nil)
  end

  defp enqueue_batch(last_id) do
    query = from(f in File, where: not f.is_private, order_by: f.id, limit: 100)
    query = if last_id, do: where(query, [f], f.id > ^last_id), else: query

    case Repo.all(query) do
      [] ->
        :ok

      batch ->
        batch |> Enum.filter(&missing?/1) |> Enum.each(&enqueue/1)
        enqueue_batch(List.last(batch).id)
    end
  end

  def store(%File{} = file) do
    with {:ok, %{body: original}} <- request(ExAws.S3.get_object(file.bucket, file.key)),
         {:ok, file} <- ensure_thumbnail(file, original) do
      ensure_variants(file, original)
    end
  end

  defp ensure_thumbnail(%File{thumb_key: key} = file, _original) when is_binary(key),
    do: {:ok, file}

  defp ensure_thumbnail(file, original) do
    key = Thumbnail.key(file.key)

    with {:ok, webp, _width} <- Thumbnail.build(original, file.context),
         {:ok, _response} <- request(put_object(file.bucket, key, webp)) do
      publish_thumbnail(file, key)
    end
  end

  defp publish_thumbnail(file, key) do
    result =
      Repo.transaction(fn ->
        case Repo.one(from(f in File, where: f.id == ^file.id, lock: "FOR UPDATE")) do
          %File{key: original_key, bucket: original_bucket, thumb_key: nil} = current
          when original_key == file.key and original_bucket == file.bucket ->
            current |> File.thumb_changeset(key) |> Repo.update!()

          _ ->
            Repo.rollback(:stale_media)
        end
      end)

    case result do
      {:ok, updated} ->
        invalidate_products(file.id)
        {:ok, updated}

      error ->
        error
    end
  end

  defp ensure_variants(%File{context: :stock} = file, _original), do: {:ok, file}

  defp ensure_variants(%File{context: :product} = file, original) do
    Enum.reduce_while(Thumbnail.product_variants(), {:ok, file}, fn requested, {:ok, current} ->
      if valid_variant?(current.variant_keys, requested) do
        {:cont, {:ok, current}}
      else
        case store_variant(current, original, requested) do
          {:ok, updated} -> {:cont, {:ok, updated}}
          error -> {:halt, error}
        end
      end
    end)
  end

  defp store_variant(file, original, 800) do
    # Legacy large thumbnails already exist. The source determines the actual width.
    with {:ok, _webp, width} <- Thumbnail.build_width(original, 800) do
      publish_variant(file, 800, file.thumb_key, width)
    end
  end

  defp store_variant(file, original, requested) do
    key = Thumbnail.variant_key(file.key, requested, original)

    with {:ok, webp, width} <- Thumbnail.build_width(original, requested),
         {:ok, _response} <- request(put_object(file.bucket, key, webp)) do
      publish_variant(file, requested, key, width)
    end
  end

  defp valid_variant?(variants, requested) do
    case is_map(variants) && Map.get(variants, to_string(requested)) do
      %{"key" => key, "width" => width} ->
        is_binary(key) and key != "" and is_integer(width) and width > 0 and width <= requested

      _ ->
        false
    end
  end

  defp publish_variant(file, requested, key, width) do
    result =
      Repo.transaction(fn ->
        case Repo.one(from(f in File, where: f.id == ^file.id, lock: "FOR UPDATE")) do
          %File{key: original_key, bucket: original_bucket, thumb_key: thumb_key} = current
          when original_key == file.key and original_bucket == file.bucket and
                 thumb_key == file.thumb_key ->
            variants =
              Map.put(current.variant_keys || %{}, to_string(requested), %{
                "key" => key,
                "width" => width
              })

            current |> File.variants_changeset(variants) |> Repo.update!()

          _ ->
            Repo.rollback(:stale_media)
        end
      end)

    case result do
      {:ok, updated} ->
        invalidate_products(file.id)
        {:ok, updated}

      error ->
        error
    end
  end

  defp invalidate_products(file_id) do
    Repo.all(from(p in Product, where: p.media_id == ^file_id, select: p.id))
    |> Enum.flat_map(&SharedOwnership.branches("Product", &1))
    |> Enum.uniq()
    |> then(fn branches ->
      if branches != [] do
        Catalogs.bump_versions(branches)
        Enum.each(branches, &Catalogs.invalidate_menu_cache/1)
      end
    end)
  end

  def delete(%File{} = file) do
    keys = [
      file.thumb_key
      | Enum.map(file.variant_keys || %{}, fn {_size, variant} ->
          if is_map(variant), do: variant["key"], else: nil
        end)
    ]

    keys
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn key, :ok ->
      case request(ExAws.S3.delete_object(file.bucket, key)) do
        {:ok, _response} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp put_object(bucket, key, body),
    do: ExAws.S3.put_object(bucket, key, body, content_type: "image/webp")

  defp request(operation), do: ExAws.request(operation)
end
