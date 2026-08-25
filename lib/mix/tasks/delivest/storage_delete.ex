defmodule Mix.Tasks.Delivest.Storage.Delete do
  @moduledoc """
  Deletes S3/MinIO buckets and all their contents.
  """
  use Mix.Task
  require Logger

  @shortdoc "Deletes specified S3/MinIO buckets and their contents"

  @default_buckets ["delivest"]

  def run(_args) do
    Mix.Task.run("app.start")

    buckets = Application.get_env(:delivest, Delivest.Storage)[:buckets] || @default_buckets

    Logger.info("[Storage.Delete] Starting bucket deletion. Target buckets: #{inspect(buckets)}")

    Enum.each(buckets, &delete_bucket/1)

    Logger.info("[Storage.Delete] Storage cleanup completed.")
  end

  defp delete_bucket(bucket) do
    Logger.info("[Storage.Delete] Clearing objects in bucket '#{bucket}'...")
    purge_objects(bucket)

    case ExAws.S3.delete_bucket(bucket) |> ExAws.request() do
      {:ok, _} ->
        Logger.info("[Storage.Delete] Bucket '#{bucket}' successfully deleted.")

      {:error, {:http_status, 404}} ->
        Logger.info("[Storage.Delete] Bucket '#{bucket}' not found (already deleted).")

      {:error, {:http_error, 404, _}} ->
        Logger.info("[Storage.Delete] Bucket '#{bucket}' not found (already deleted).")

      error ->
        Logger.error("[Storage.Delete] Failed to delete bucket '#{bucket}': #{inspect(error)}")
    end
  end

  defp purge_objects(bucket) do
    case ExAws.S3.list_objects(bucket) |> ExAws.request() do
      {:ok, %{body: %{contents: objects}}} when is_list(objects) and objects != [] ->
        Enum.each(objects, fn %{key: key} ->
          ExAws.S3.delete_object(bucket, key) |> ExAws.request!()
          Logger.info("[Storage.Delete] Deleted object: #{key}")
        end)

      _ ->
        :ok
    end
  end
end
