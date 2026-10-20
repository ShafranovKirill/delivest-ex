defmodule DelivestWeb.Staff.LogLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Audit
  alias Delivest.Logs.Entry
  alias Delivest.Repo

  defp login(conn, permissions, session \\ %{}) do
    staff = insert(:staff, name: "Ivan", role: insert(:role, permissions: permissions))
    conn = init_test_session(conn, Map.merge(%{"staff_id" => staff.id}, session))
    {conn, staff}
  end

  defp log(level, message),
    do: Repo.insert!(%Entry{level: level, message: message, inserted_at: DateTime.utc_now()})

  test "events describe who did what", %{conn: conn} do
    {conn, staff} = login(conn, ["logs.read"])
    Audit.record(staff, "product.created", insert(:product, name: "Borsch"))

    {:ok, _lv, html} = live(conn, ~p"/staff/logs")

    assert html =~ "Staff Ivan"
    assert html =~ "Product «Borsch» created"
  end

  test "events follow the staff language", %{conn: conn} do
    {conn, staff} = login(conn, ["logs.read"], %{"locale" => "ru"})
    Audit.record(staff, "product.created", insert(:product, name: "Borsch"))

    {:ok, _lv, html} = live(conn, ~p"/staff/logs")

    assert html =~ "Сотрудник Ivan"
    assert html =~ "Создан товар «Borsch»"
  end

  test "new events appear without reload", %{conn: conn} do
    {conn, staff} = login(conn, ["logs.read"])
    {:ok, lv, _html} = live(conn, ~p"/staff/logs")

    Audit.record(staff, "staff.logged_in", staff)

    assert render(lv) =~ "Signed in"
  end

  test "tabs split raw logs, errors and hints", %{conn: conn} do
    {conn, _staff} = login(conn, ["logs.read"])
    log("error", "database exploded")
    log("warning", "product.updated failed")
    log("info", "GET /staff/logs")

    {:ok, _lv, errors} = live(conn, ~p"/staff/logs/errors")
    assert errors =~ "database exploded"
    refute errors =~ "product.updated failed"

    {:ok, _lv, hints} = live(conn, ~p"/staff/logs/hints")
    assert hints =~ "product.updated failed"
    refute hints =~ "database exploded"

    {:ok, lv, raw} = live(conn, ~p"/staff/logs/raw")
    assert raw =~ "GET /staff/logs"

    html = lv |> form("#logs-filter", %{"q" => "exploded"}) |> render_change()
    assert_patch(lv, ~p"/staff/logs/raw?q=exploded")
    assert render(lv) =~ "database exploded"
    refute html =~ "GET /staff/logs"
  end

  test "staff without permission is redirected", %{conn: conn} do
    {conn, _staff} = login(conn, ["orders.read"])

    assert {:error, {:redirect, %{to: "/staff/dashboard"}}} = live(conn, ~p"/staff/logs")
  end
end
