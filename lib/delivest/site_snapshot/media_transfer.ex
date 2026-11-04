defmodule Delivest.SiteSnapshot.MediaTransfer do
  @moduledoc """
  Downloads snapshot originals, stores new objects with content-addressed keys
  and removes only the objects created by the current attempt.
  """

  require Logger

  alias Delivest.Media
  alias Delivest.SiteSnapshot.{Archive, Assets}

  def export_branch_blobs(data) do
    files = Enum.map(data["media"], &{&1["bucket"], &1["key"]})
    raw = Enum.map(Assets.branch_keys(data), &{Media.public_bucket(), &1})
    refs = Enum.uniq(files ++ raw)

    if Enum.any?(data["media"], &(&1["is_private"] != false)) do
      {:error, :private_media}
    else
      fetch_blobs(refs)
    end
  end

  def export_franchise_blobs(data) do
    files =
      Enum.flat_map(data["branches"], fn branch ->
        Enum.map(branch["media"] || [], &{&1["bucket"], &1["key"]})
      end)

    raw = Enum.map(Assets.franchise_keys(data), &{data["public_bucket"], &1})
    refs = Enum.uniq(files ++ raw)
    private? = Enum.any?(data["branches"], &Assets.private_media?/1)

    if private?, do: {:error, :private_media}, else: fetch_blobs(refs)
  end

  def fetch_blobs(refs) do
    max_file = Archive.max_file()
    max_archive = Archive.max_archive()

    if length(refs) > Archive.max_files() do
      {:error, :archive_too_large}
    else
      Enum.reduce_while(refs, {:ok, %{}, 0}, fn {bucket, key}, {:ok, acc, total} ->
        case ExAws.S3.get_object(bucket, key) |> ExAws.request() do
          {:ok, %{body: body}}
          when byte_size(body) <= max_file and total + byte_size(body) <= max_archive ->
            if Assets.image_type(body) do
              {:cont, {:ok, Map.put(acc, "#{bucket}/#{key}", body), total + byte_size(body)}}
            else
              {:halt, {:error, {:missing_media, bucket, key}}}
            end

          {:ok, _} ->
            {:halt, {:error, :archive_too_large}}

          _ ->
            {:halt, {:error, {:missing_media, bucket, key}}}
        end
      end)
      |> case do
        {:ok, blobs, _total} -> {:ok, blobs}
        error -> error
      end
    end
  end

  def upload_blobs(blobs) do
    Enum.reduce_while(blobs, {:ok, %{}, []}, fn {reference, body}, {:ok, mapping, keys} ->
      key = Assets.storage_key(reference, body)
      bucket = Media.public_bucket()

      result =
        case ExAws.S3.get_object(bucket, key) |> ExAws.request() do
          {:ok, %{body: existing}} when existing == body ->
            :existing

          {:ok, _} ->
            {:error, :media_conflict}

          {:error, {:http_error, 404, _}} ->
            ExAws.S3.put_object(bucket, key, body, content_type: Assets.image_type(body))
            |> ExAws.request()

          error ->
            error
        end

      mapping = Map.put(mapping, reference, key)

      mapping =
        case Assets.icon_directory(reference, key) do
          {source_dir, target_dir} -> Map.put(mapping, source_dir, target_dir)
          nil -> mapping
        end

      case result do
        :existing ->
          {:cont, {:ok, mapping, keys}}

        {:ok, _} ->
          {:cont, {:ok, mapping, [key | keys]}}

        _ ->
          cleanup(keys)
          {:halt, {:error, :media_upload_failed}}
      end
    end)
    |> case do
      {:ok, mapping, keys} -> {:ok, mapping, keys}
      error -> error
    end
  end

  def cleanup([]), do: :ok

  def cleanup(keys) do
    failed =
      Enum.reject(keys, fn key ->
        case ExAws.S3.delete_object(Media.public_bucket(), key) |> ExAws.request() do
          {:ok, _} -> true
          _ -> false
        end
      end)

    if failed != [] do
      Logger.warning("Site snapshot could not clean up uploaded images: #{inspect(failed)}")
    end

    :ok
  end

  def mapped_key(nil, _uploaded, _source_bucket), do: nil

  def mapped_key(key, uploaded, source_bucket) do
    case Map.fetch(uploaded, "#{source_bucket}/#{key}") do
      {:ok, new_key} -> new_key
      :error -> throw({:snapshot_abort, :missing_media})
    end
  end
end
