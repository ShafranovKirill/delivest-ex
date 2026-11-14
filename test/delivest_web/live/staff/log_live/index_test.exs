defmodule DelivestWeb.Staff.LogLive.IndexTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Audit
  alias Delivest.Logs.Entry
  alias Delivest.Repo

  defp login(conn, permissions, session \\ %{}) do
    staff = insert(:staff, name: "Ivan", role: insert(:role, permissions: permissions))
    conn = init_test_session(conn, Map.merge(%{"staff_id" => staff.id}, session))
    {conn, staff}
  end

  defp log(level, message, metadata \\ %{}) do
    Repo.insert!(%Entry{
      level: level,
      message: message,
      metadata: metadata,
      inserted_at: DateTime.utc_now()
    })
  end

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

  test "status change shows where the order went from and to", %{conn: conn} do
    {conn, staff} = login(conn, ["logs.read"], %{"locale" => "ru"})
    order = order_fixture(insert(:branch).id)

    Audit.record(staff, "order.status_changed", order,
      metadata: %{from: "accepted", to: "preparing"}
    )

    Audit.record(staff, "order.status_changed", order,
      metadata: %{from: "preparing", to: "cancelled", reason: "Нет продуктов"}
    )

    {:ok, _lv, html} = live(conn, ~p"/staff/logs")

    assert html =~ "Заказ ##{order.number}: Подтверждён → Готовится"
    assert html =~ "причина: Нет продуктов"
  end

  test "events filter by employee, event and branch and sort by branch", %{conn: conn} do
    {conn, staff} = login(conn, ["logs.read"])
    other = insert(:staff, name: "Petr")
    alpha = insert(:branch, name: "Alpha")
    beta = insert(:branch, name: "Beta")

    Audit.record(staff, "product.created", insert(:product, name: "Borsch"), branch_id: beta.id)
    Audit.record(other, "product.deleted", insert(:product, name: "Pelmeni"), branch_id: alpha.id)

    {:ok, lv, _html} = live(conn, ~p"/staff/logs?actor=#{other.id}")
    html = render(lv)
    assert html =~ "Pelmeni"
    refute html =~ "Borsch"

    {:ok, lv, _html} = live(conn, ~p"/staff/logs?action=product.created")
    assert render(lv) =~ "Borsch"
    refute render(lv) =~ "Pelmeni"

    {:ok, lv, _html} = live(conn, ~p"/staff/logs?branch=#{beta.id}")
    assert render(lv) =~ "Borsch"
    refute render(lv) =~ "Pelmeni"

    {:ok, _lv, html} = live(conn, ~p"/staff/logs?sort=branch")
    [first, _second] = Regex.scan(~r/Borsch|Pelmeni/, html) |> Enum.map(&hd/1) |> Enum.uniq()
    assert first == "Pelmeni"
  end

  test "new events appear without reload", %{conn: conn} do
    {conn, staff} = login(conn, ["logs.read"])
    {:ok, lv, _html} = live(conn, ~p"/staff/logs")

    Audit.record(staff, "staff.logged_in", staff)

    assert render(lv) =~ "Signed in"
  end

  test "nested CRM warnings render in the audit events table", %{conn: conn} do
    {conn, _staff} = login(conn, ["logs.read"])
    order = order_fixture(insert(:branch).id)
    warnings = %{"invalid_product_keys" => [0]}

    Audit.record(:system, "order.sent_to_crm", order,
      metadata: %{external_id: "crm-1", warnings: warnings}
    )

    Audit.record(:system, "order.crm_status_changed", order, metadata: %{warnings: warnings})

    {:ok, lv, _html} = live(conn, ~p"/staff/logs")
    assert has_element?(lv, "#audit-events", ~r/invalid_product_keys/)
  end

  test "tabs split raw logs and errors", %{conn: conn} do
    {conn, _staff} = login(conn, ["logs.read"])
    log("error", "database exploded")
    log("warning", "product.updated failed")
    log("info", "GET /staff/logs")

    {:ok, _lv, errors} = live(conn, ~p"/staff/logs/errors")
    assert errors =~ "database exploded"
    refute errors =~ "product.updated failed"

    {:ok, lv, raw} = live(conn, ~p"/staff/logs/raw")
    assert raw =~ "GET /staff/logs"

    html = lv |> form("#logs-filter", %{"q" => "exploded"}) |> render_change()
    assert_patch(lv, ~p"/staff/logs/raw?q=exploded")
    assert render(lv) =~ "database exploded"
    refute html =~ "GET /staff/logs"
  end

  test "malformed URL filters are ignored and raw search can reset", %{conn: conn} do
    {conn, _staff} = login(conn, ["logs.read"])
    log("error", "Resettable entry")

    {:ok, lv, _} =
      live(conn, "/staff/logs/raw?q[secret]=value&page[bad]=1&page_size=500&sort=unknown")

    assert has_element?(lv, "#app-logs", "Resettable entry")

    lv |> form("#logs-filter", %{"q" => "no match"}) |> render_change()
    assert_patch(lv, ~p"/staff/logs/raw?q=no+match")
    refute has_element?(lv, "#app-logs", "Resettable entry")

    lv |> element(~s(button[phx-click="reset_entries"])) |> render_click()
    assert_patch(lv, ~p"/staff/logs/raw")
    assert has_element?(lv, "#app-logs", "Resettable entry")
  end

  test "raw logs hide known credential values in message and metadata", %{conn: conn} do
    {conn, _staff} = login(conn, ["logs.read"])

    log("error", "Request failed api_key=super-secret Authorization: Bearer abc123", %{
      "access_token" => "another-secret",
      "request" => %{"password" => "nested-secret", "path" => "/staff/logs"}
    })

    {:ok, _lv, html} = live(conn, ~p"/staff/logs/raw")

    assert html =~ "[REDACTED]"
    assert html =~ "/staff/logs"
    refute html =~ "super-secret"
    refute html =~ "abc123"
    refute html =~ "another-secret"
    refute html =~ "nested-secret"
  end

  test "staff without permission is redirected", %{conn: conn} do
    {conn, _staff} = login(conn, ["orders.read"])

    assert {:error, {:redirect, %{to: "/staff"}}} = live(conn, ~p"/staff/logs")
  end
end
