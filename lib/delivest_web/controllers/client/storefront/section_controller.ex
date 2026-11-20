defmodule DelivestWeb.Client.Storefront.SectionController do
  use DelivestWeb, :controller

  alias Delivest.Storefront

  @cache_control "public, no-cache, must-revalidate"

  def show(conn, %{"section" => section} = params) do
    case Storefront.section(section, params) do
      {:ok, response} ->
        tag = etag(section, params, response.revision)

        conn =
          conn
          |> put_resp_header("cache-control", @cache_control)
          |> put_resp_header("etag", tag)
          |> put_resp_header("x-storefront-valid-until", response.valid_until)
          |> put_resp_header("access-control-expose-headers", "ETag, X-Storefront-Valid-Until")

        if matches?(get_req_header(conn, "if-none-match"), tag),
          do: send_resp(conn, :not_modified, ""),
          else: json(conn, response)

      {:error, :not_found} ->
        error(conn, :not_found, "branch_not_found")

      {:error, :invalid_branch} ->
        error(conn, :bad_request, "invalid_branch_id")

      {:error, :unknown_section} ->
        error(conn, :not_found, "section_not_found")

      _ ->
        error(conn, :service_unavailable, "storefront_unavailable")
    end
  end

  defp error(conn, status, reason) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> json(%{error: reason})
  end

  defp etag(section, params, revision) do
    scope =
      if section in ~w(menu stories advertising),
        do: elem(Ecto.UUID.cast(params["branch_id"]), 1),
        else: "*"

    locale =
      if section == "menu" and params["locale"] in ~w(ru en),
        do: params["locale"],
        else: if(section == "menu", do: DelivestWeb.Plugs.Locale.default_locale(), else: "*")

    digest = :crypto.hash(:sha256, "1:#{section}:#{scope}:#{locale}:#{revision}")
    ~s(W/"#{Base.url_encode64(digest, padding: false)}")
  end

  defp matches?(headers, tag) do
    expected = String.replace_prefix(tag, "W/", "")

    Enum.any?(headers, fn header ->
      header
      |> String.split(",")
      |> Enum.any?(fn candidate ->
        candidate = String.trim(candidate)
        candidate == "*" or String.replace_prefix(candidate, "W/", "") == expected
      end)
    end)
  end
end
