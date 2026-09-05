defmodule DelivestWeb.Helpers.CookieHelper do
  import Plug.Conn

  def put_cookie(conn, key, value, overrides \\ []) do
    opts = build_options(overrides)
    put_resp_cookie(conn, key, value, opts)
  end

  def delete_cookie(conn, key, overrides \\ []) do
    opts = build_options(overrides)
    delete_resp_cookie(conn, key, opts)
  end

  defp build_options(overrides) do
    default_env_options()
    |> Keyword.merge(overrides)
  end

  defp default_env_options do
    if Mix.env() in [:dev, :test] do
      [
        max_age: 30 * 24 * 60 * 60,
        path: "/",
        secure: false,
        same_site: "Lax",
        http_only: true
      ]
    else
      [
        max_age: 30 * 24 * 60 * 60,
        path: "/",
        secure: true,
        same_site: "Lax",
        http_only: true
      ]
    end
  end
end
