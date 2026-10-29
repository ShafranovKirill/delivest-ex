defmodule DelivestWeb.Staff.StaffPwaTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  alias Delivest.{PushClient, Repo}
  alias Delivest.Push.StaffSubscription

  test "the admin is installable from /staff", %{conn: conn} do
    manifest = conn |> get(~p"/staff/manifest.webmanifest") |> json_response(200)

    assert %{"scope" => "/staff/", "start_url" => "/staff", "display" => "standalone"} = manifest
    assert [%{"sizes" => "192x192"}, %{"sizes" => "512x512"}] = manifest["icons"]

    worker = get(build_conn(), ~p"/staff/sw.js")
    assert worker.status == 200
    assert get_resp_header(worker, "content-type") |> hd() =~ "javascript"
    assert get_resp_header(worker, "service-worker-allowed") == ["/staff/"]
    assert worker.resp_body =~ "notificationclick"
  end

  test "a signed in staff subscribes and unsubscribes the device", %{conn: conn} do
    staff = insert(:staff)
    conn = init_test_session(conn, %{"staff_id" => staff.id})
    attrs = PushClient.new().attrs

    assert conn |> post(~p"/staff/push/subscriptions", attrs) |> response(204)
    assert [%StaffSubscription{staff_id: staff_id}] = Repo.all(StaffSubscription)
    assert staff_id == staff.id

    assert conn |> post(~p"/staff/push/subscriptions", attrs) |> response(204)
    assert Repo.aggregate(StaffSubscription, :count) == 1

    assert conn
           |> delete(~p"/staff/push/subscriptions", %{"endpoint" => attrs["endpoint"]})
           |> response(204)

    assert Repo.all(StaffSubscription) == []
  end

  test "a guest cannot subscribe", %{conn: conn} do
    assert conn |> post(~p"/staff/push/subscriptions", PushClient.new().attrs) |> response(401)
  end

  test "a malformed subscription is refused", %{conn: conn} do
    conn = init_test_session(conn, %{"staff_id" => insert(:staff).id})

    assert conn
           |> post(~p"/staff/push/subscriptions", %{"endpoint" => "http://x", "keys" => %{}})
           |> response(422)
  end
end
