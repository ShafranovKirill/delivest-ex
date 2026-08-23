defmodule Delivest.Media do
  alias Delivest.Media.File
  alias Delivest.Repo

  @spec generate_upload_url(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def generate_upload_url(bucket, key) do
    public_config = get_public_config()
    ExAws.S3.presigned_url(public_config, :put, bucket, key, expires_in: 900)
  end

  @spec generate_download_url(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def generate_download_url(bucket, key) do
    public_config = get_public_config()
    ExAws.S3.presigned_url(public_config, :get, bucket, key, expires_in: 900)
  end

  defp get_public_config do
    config = ExAws.Config.new(:s3)
    media_conf = Application.get_env(:delivest, Delivest.Media, [])

    host = media_conf[:public_host] || config.host

    port =
      case media_conf[:public_port] do
        nil -> config.port
        p when is_binary(p) -> String.to_integer(p)
        p -> p
      end

    %{config | host: host, port: port}
  end

  @spec create_file(map()) :: {:ok, File.t()} | {:error, Ecto.Changeset.t()}
  def create_file(attrs) do
    %File{}
    |> File.changeset(attrs)
    |> Repo.insert()
  end

  @spec delete_file(File.t()) :: {:ok, File.t()} | {:error, term()}
  def delete_file(%File{} = file) do
    case ExAws.S3.delete_object(file.bucket, file.key) |> ExAws.request() do
      {:ok, _} ->
        Repo.delete(file)

      error ->
        error
    end
  end

  def delete_file_by_key(key) do
    case Repo.get_by(File, key: key) do
      %File{} = file -> delete_file(file)
      nil -> {:ok, nil}
    end
  end
end
