defmodule DelivestWeb.Staff.AuthLive.LoginTest do
  use DelivestWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  import Delivest.Factory

  describe "Login page" do
    test "renders login page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/staff/auth/login")

      assert html =~ "Welcome to Delivest CRM"
      assert html =~ "Sign in to your account to continue"
      assert html =~ "login"
      assert html =~ "Password"
      assert html =~ "Log in"
    end

    test "redirects if user is already logged in", %{conn: conn} do
      user = insert(:staff)

      conn = init_test_session(conn, %{"staff_id" => user.id})

      assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/staff/auth/login")
    end

    test "shows validation errors on change (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/staff/auth/login")

      html =
        lv
        |> form("#user", %{
          "user" => %{"login" => "a", "password" => "123"}
        })
        |> render_change()

      assert html =~ "must be at least 8 characters long"
    end

    test "shows invalid credentials error on submit if user does not exist", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/staff/auth/login")

      html =
        lv
        |> form("#user", %{
          "user" => %{"login" => "valid_login", "password" => "Password123!"}
        })
        |> render_submit()

      assert html =~ "Invalid login or password"
    end

    test "sets trigger_action to true on valid submit", %{conn: conn} do
      insert(:staff, login: "test_staff")

      {:ok, lv, _html} = live(conn, ~p"/staff/auth/login")

      html =
        lv
        |> form("#user", %{
          "user" => %{"login" => "test_staff", "password" => "Password123!"}
        })
        |> render_submit()

      assert html =~ "phx-trigger-action"
    end
  end
end
