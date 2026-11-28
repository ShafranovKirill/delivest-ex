defmodule Delivest.ManagedBootstrapTest do
  use Delivest.DataCase, async: false

  alias Delivest.Identity.Staff
  alias Delivest.Release

  test "managed bootstrap creates one admin with the Node-generated password and can repeat" do
    password = "Aa1!" <> String.duplicate("a1b2c3", 8)
    old_password = System.get_env("ADMIN_PASSWORD")
    old_login = System.get_env("ADMIN_LOGIN")
    System.put_env("ADMIN_PASSWORD", password)
    System.put_env("ADMIN_LOGIN", "stage3admin")

    on_exit(fn ->
      if old_password,
        do: System.put_env("ADMIN_PASSWORD", old_password),
        else: System.delete_env("ADMIN_PASSWORD")

      if old_login,
        do: System.put_env("ADMIN_LOGIN", old_login),
        else: System.delete_env("ADMIN_LOGIN")
    end)

    Req.Test.stub(Delivest.S3Stub, fn conn -> Plug.Conn.send_resp(conn, 200, "") end)

    assert :ok = Release.setup_managed()
    assert %Staff{login: "stage3admin"} = staff = Repo.one!(Staff)
    assert Argon2.verify_pass(password, staff.password_hash)

    assert :ok = Release.setup_managed()
    assert Repo.aggregate(Staff, :count, :id) == 1
  end
end
