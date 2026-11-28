defmodule DelivestWeb.Helpers.CookieHelperManagedTest do
  use ExUnit.Case, async: false

  alias DelivestWeb.Helpers.CookieHelper

  test "managed client cookies can be sent from an external HTTPS storefront" do
    old_env = Application.get_env(:delivest, :environment)
    old_path = Application.get_env(:delivest, :public_site_config_path)
    Application.put_env(:delivest, :environment, :prod)
    Application.put_env(:delivest, :public_site_config_path, "/tmp/managed-cookie-test")

    on_exit(fn ->
      Application.put_env(:delivest, :environment, old_env)
      Application.put_env(:delivest, :public_site_config_path, old_path)
    end)

    conn = Plug.Test.conn(:get, "/") |> CookieHelper.put_cookie("session_id", "guest")
    cookie = conn.resp_cookies["session_id"]
    assert cookie.same_site == "None"
    assert cookie.secure == true
    assert cookie.http_only == true

    branch =
      Plug.Test.conn(:get, "/")
      |> CookieHelper.put_cookie("active_branch_id", "branch", http_only: false, same_site: "Lax")

    assert branch.resp_cookies["active_branch_id"].same_site == "None"
    refute branch.resp_cookies["active_branch_id"].http_only
  end
end
