defmodule Delivest.ManagedStorage do
  @moduledoc "Checks both the internal S3 service and public HTTPS media route."

  alias Delivest.Media

  def check! do
    adapter = Application.get_env(:delivest, :managed_storage_probe_adapter, __MODULE__)
    adapter.run!()
  end

  def run! do
    key = "checks/#{Ecto.UUID.generate()}"
    public = Media.public_bucket()
    private = Media.private_bucket()
    body = "delivest-storage-probe"
    uploaded_body = "delivest-public-upload-probe"

    try do
      request!(ExAws.S3.put_object(public, key, body))
      request!(ExAws.S3.put_object(private, key, body))

      with {:ok, public_url} <- Media.generate_public_url(public, key),
           {:ok, upload_url} <- Media.generate_upload_url(public, key),
           {:ok, private_url} <- Media.generate_download_url(private, key) do
        {upload_status, _} = http!(:put, upload_url, uploaded_body)
        {public_status, public_body} = http!(:get, public_url)
        {private_status, private_body} = http!(:get, private_url)
        public_upload = upload_status in 200..299
        public_read = public_status in 200..299 and public_body == uploaded_body
        private_signed = private_status in 200..299 and private_body == body

        case http!(:get, strip_signature(private_url)) do
          {status, _} when status in [401, 403, 404] -> :ok
          _ -> raise "private media is anonymously accessible"
        end

        if not (public_upload and public_read and private_signed),
          do: raise("public media check failed")

        %{
          "public_upload" => true,
          "public_read" => true,
          "private_signed" => true,
          "internal_endpoint" => true
        }
      else
        _ -> raise "media URL generation failed"
      end
    after
      ExAws.S3.delete_object(public, key) |> ExAws.request()
      ExAws.S3.delete_object(private, key) |> ExAws.request()
    end
  end

  defp request!(operation) do
    case ExAws.request(operation) do
      {:ok, _} -> :ok
      _ -> raise "internal S3 request failed"
    end
  end

  defp http!(method, url, body \\ nil) do
    if URI.parse(url).scheme != "https", do: raise("public media URL must use HTTPS")

    options = [
      method: method,
      url: url,
      body: body,
      retry: false,
      redirect: false,
      receive_timeout: 10_000
    ]

    adapter = Application.get_env(:delivest, :managed_storage_http_adapter, Req)

    options =
      Keyword.merge(options, Application.get_env(:delivest, :managed_storage_req_options, []))

    case adapter.request(options) do
      {:ok, %{status: status, body: response_body}} -> {status, response_body}
      _ -> raise "public media HTTPS request failed"
    end
  end

  defp strip_signature(url) do
    parsed = URI.parse(url)
    URI.to_string(%{parsed | query: nil})
  end
end
