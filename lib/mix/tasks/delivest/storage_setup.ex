defmodule Mix.Tasks.Delivest.StorageSetup do
  @moduledoc """
  Automatically creates S3/MinIO buckets and applies public policies.
  """
  use Mix.Task
  require Logger

  @shortdoc "Creates necessary S3/MinIO buckets and applies public policies"

  @default_buckets ["delivest"]

  def run(_args) do
    Mix.Task.run("app.start")

    buckets = Application.get_env(:delivest, Delivest.Storage)[:buckets] || @default_buckets

    Logger.info("[Storage.Setup] Starting storage setup. Target buckets: #{inspect(buckets)}")

    Enum.each(buckets, &setup_bucket/1)

    Logger.info("[Storage.Setup] Storage setup completed.")
  end

  defp setup_bucket(bucket) do
    Logger.info("[Storage.Setup] Ensuring bucket '#{bucket}' exists...")

    case ExAws.S3.put_bucket(bucket, "") |> ExAws.request() do
      {:ok, _response} ->
        Logger.info("[Storage.Setup] Bucket '#{bucket}' successfully created.")
        apply_policy(bucket)

      {:error, error} ->
        error_str = inspect(error)

        if String.contains?(error_str, "BucketAlreadyOwnedByYou") or
             String.contains?(error_str, "BucketAlreadyExists") or
             String.contains?(error_str, "409") do
          Logger.info("[Storage.Setup] Bucket '#{bucket}' already exists. Applying policy...")
          apply_policy(bucket)
        else
          Logger.error("[Storage.Setup] Error creating bucket '#{bucket}': #{error_str}")
        end
    end
  end

  defp apply_policy(bucket) do
    Logger.info("[Storage.Setup] Applying public read policy to '#{bucket}/public/*'...")

    policy = %{
      "Version" => "2012-10-17",
      "Statement" => [
        %{
          "Sid" => "PublicReadGetObject",
          "Effect" => "Allow",
          "Principal" => "*",
          "Action" => ["s3:GetObject"],
          "Resource" => ["arn:aws:s3:::#{bucket}/public/*"]
        }
      ]
    }

    policy_json = Jason.encode!(policy)

    case ExAws.S3.put_bucket_policy(bucket, policy_json) |> ExAws.request() do
      {:ok, _response} ->
        Logger.info("[Storage.Setup] Policy successfully applied.")

      {:error, error} ->
        Logger.error("[Storage.Setup] Failed to apply policy: #{inspect(error)}")
    end
  end
end
