defmodule DelivestWeb.LocaleController do
  use DelivestWeb, :controller

  def set(conn, %{"locale" => locale}) do
    if locale in DelivestWeb.Plugs.Locale.supported_locales() do
      conn
      |> put_session(:locale, locale)
      |> redirect(to: return_path(conn))
    else
      redirect(conn, to: return_path(conn))
    end
  end

  defp return_path(conn) do
    case get_req_header(conn, "referer") do
      [referer | _] -> URI.parse(referer).path || "/"
      _ -> "/"
    end
  end
end
