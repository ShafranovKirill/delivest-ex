defmodule DelivestWeb.AdvertisingDestination do
  @moduledoc "Builds a client redirect from trusted server configuration and a stored branch slug."

  alias DelivestWeb.Seo.SeoSite

  def for_branch(slug) when is_binary(slug) do
    origin = SeoSite.origin()

    if is_binary(origin) do
      uri = URI.parse(origin)

      if uri.scheme in ["https", "http"] and is_binary(uri.host) and uri.host != "" and
           is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) and
           uri.path in [nil, "", "/"] and
           (uri.scheme == "https" or uri.host in ["localhost", "127.0.0.1"]) do
        {:ok,
         String.trim_trailing(origin, "/") <> "/" <> URI.encode(slug, &URI.char_unreserved?/1)}
      else
        {:error, :invalid_origin}
      end
    else
      {:error, :invalid_origin}
    end
  end

  def for_branch(_), do: {:error, :invalid_origin}
end
