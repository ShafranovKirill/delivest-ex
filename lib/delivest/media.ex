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

  def prepare_upload(group_name, context, filename) do
    bucket = Application.get_env(:delivest, Delivest.Media)[:bucket] || "delivest-uploads"
    ext = Path.extname(filename)
    unique_name = "#{Ecto.UUID.generate()}_#{System.system_time(:millisecond)}#{ext}"
    key = "#{context}/#{group_name}/#{unique_name}"

    case generate_upload_url(bucket, key) do
      {:ok, presigned_url} ->
        {:ok, download_url} = generate_download_url(bucket, key)

        {:ok,
         %{
           bucket: bucket,
           key: key,
           url_for_saved_entry: download_url,
           url: presigned_url,
           presigned_url: presigned_url
         }}

      {:error, reason} ->
        {:error, reason}
    end
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

  @spec get_file(binary() | nil) :: File.t() | nil
  def get_file(nil), do: nil

  def get_file(id) do
    Repo.get(File, id)
  end

  def delete_file_by_key(key) do
    case Repo.get_by(File, key: key) do
      %File{} = file -> delete_file(file)
      nil -> {:ok, nil}
    end
  end

  @spec get_url(String.t() | nil) :: String.t() | nil
  def get_url(nil), do: nil

  def get_url(media_id) when is_binary(media_id) do
    case Repo.get(File, media_id) do
      %File{bucket: bucket, key: key} ->
        case generate_download_url(bucket, key) do
          {:ok, url} -> url
          _ -> nil
        end

      nil ->
        nil
    end
  end
end
