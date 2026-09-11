defmodule DelivestWeb.Helpers.CookieHelper do
  import Plug.Conn

  def get_cookie(conn, key) do
    conn = fetch_cookies(conn)
    Map.get(conn.cookies, to_string(key))
  end

  def put_cookie(conn, key, value, overrides \\ []) do
    string_value = to_string(value)
    opts = build_options(overrides)
    put_resp_cookie(conn, to_string(key), string_value, opts)
  end

  def delete_cookie(conn, key, overrides \\ []) do
    opts = build_options(overrides)
    delete_resp_cookie(conn, to_string(key), opts)
  end

  defp build_options(overrides) do
    default_env_options()
    |> Keyword.merge(overrides)
  end

  defp default_env_options do
    env = Application.get_env(:delivest, :environment, :dev)

    if env in [:dev, :test] do
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
