defmodule DelivestWeb.Staff.IntegrationLive.RecoveryTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Events.{Delivery, Event}
  alias Delivest.Integrations.Crm.CommandDelivery
  alias Delivest.Oms.Order.CrmSync
  alias Delivest.Repo

  defp branch do
    suffix = System.unique_integer([:positive])
    insert(:branch, name: "Recovery #{suffix}", slug: "recovery-#{suffix}", code: "R#{suffix}")
  end

  defp sign_in(conn, branch, permissions) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
  end

  test "authorized branch operator sees bounded manual recovery and confirmation controls", %{
    conn: conn
  } do
    branch = branch()
    order = order_fixture(branch.id)

    event =
      Repo.insert!(%Event{
        type: "order.status_changed",
        aggregate_type: "order",
        aggregate_id: order.id,
        branch_id: branch.id
      })

    delivery = Repo.insert!(%Delivery{event_id: event.id, subscriber: "crm", status: "blocked"})

    command =
      Repo.insert!(%CommandDelivery{
        job_id: System.unique_integer([:positive]),
        branch_id: branch.id,
        order_id: order.id,
        phase: "unknown"
      })

    conn = sign_in(conn, branch, ["integrations.read", "orders.update"])

    {:ok, index, _} = live(conn, ~p"/staff/b/#{branch}/integrations")
    assert has_element?(index, "#integration-recovery")

    {:ok, recovery, _} = live(conn, ~p"/staff/b/#{branch}/integrations/recovery")
    assert has_element?(recovery, "#recovery-events")
    assert has_element?(recovery, "#recovery-commands")
    refute has_element?(recovery, "#recovery-confirm")
    assert has_element?(recovery, "#event-done-event-#{event.id}-crm")
    assert has_element?(recovery, "#command-done-command-#{command.job_id}")

    recovery |> element("#event-done-event-#{event.id}-crm") |> render_click()
    assert has_element?(recovery, "#recovery-confirm")

    assert Repo.get_by!(Delivery, event_id: delivery.event_id, subscriber: delivery.subscriber).status ==
             "blocked"

    recovery |> element("#recovery-confirm-button") |> render_click()

    assert Repo.get_by!(Delivery, event_id: delivery.event_id, subscriber: delivery.subscriber).status ==
             "delivered"

    recovery |> element("#command-done-command-#{command.job_id}") |> render_click()
    recovery |> element("#recovery-confirm-button") |> render_click()
    assert Repo.reload!(command).phase == "done"
    recovery |> element("#recovery-refresh") |> render_click()
  end

  test "read-only staff cannot enter manual recovery", %{conn: conn} do
    branch = branch()
    conn = sign_in(conn, branch, ["integrations.read"])

    {:ok, index, _} = live(conn, ~p"/staff/b/#{branch}/integrations")
    refute has_element?(index, "#integration-recovery")
    assert {:error, {:redirect, _}} = live(conn, ~p"/staff/b/#{branch}/integrations/recovery")
  end

  test "staff cannot enter another branch's recovery", %{conn: conn} do
    branch = branch()
    other = branch()
    conn = sign_in(conn, branch, ["integrations.read", "orders.update"])

    assert {:error, {:redirect, _}} = live(conn, ~p"/staff/b/#{other}/integrations/recovery")
  end

  test "a stale CRM send appears only in its branch and opens existing order resolution", %{
    conn: conn
  } do
    branch = branch()
    other = branch()
    stale = DateTime.add(DateTime.utc_now(:second), -700, :second)

    own =
      branch.id
      |> order_fixture()
      |> Ecto.Changeset.change(
        crm: %CrmSync{provider: "frontpad", status: "sending", sending_started_at: stale}
      )
      |> Repo.update!()

    foreign =
      other.id
      |> order_fixture()
      |> Ecto.Changeset.change(
        crm: %CrmSync{provider: "frontpad", status: "sending", sending_started_at: stale}
      )
      |> Repo.update!()

    conn = sign_in(conn, branch, ["orders.update"])
    {:ok, recovery, _} = live(conn, ~p"/staff/b/#{branch}/integrations/recovery")

    assert has_element?(recovery, "#recovery-syncs")

    assert has_element?(
             recovery,
             "#sync-open-#{own.id}[href='/staff/b/#{branch.slug}/orders/#{own.id}']"
           )

    refute has_element?(recovery, "#sync-open-#{foreign.id}")
    assert Repo.reload!(own).crm.status == "unknown"
    assert Repo.reload!(foreign).crm.status == "sending"
  end
end
