defmodule Delivest.Integrations.Crm.ReconciliationTest do
  use Delivest.DataCase, async: true
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory

  alias Delivest.Audit.Event
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Integrations.Crm.Reconciliation
  alias Delivest.Integrations.Frontpad
  alias Delivest.Oms
  alias Delivest.Oms.{Carts, Orders}

  setup do
    branch = insert(:branch, is_active: true)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Frontpad.Settings{api_key: "key"}
      }
    })

    product = insert_branch_product(branch.id, price: 100)
    {:ok, cart} = Carts.create_cart(%{branch_id: branch.id})
    {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)

    {:ok, order} =
      Oms.create_order(%{
        "cart_id" => cart.id,
        "branch_id" => branch.id,
        "fulfillment_type" => "pickup",
        "payment_method" => "cash"
      })

    {:ok, order} = Orders.update_order_crm(order, %{status: "unknown", alert: "Check CRM"})

    staff =
      insert(:staff, role: insert(:role, permissions: ["orders.update"]), branches: [branch])

    %{branch: branch, order: order, staff: staff}
  end

  test "resend is audited once and cannot be repeated", %{
    branch: branch,
    order: order,
    staff: staff
  } do
    assert {:ok, _} = Reconciliation.resolve(staff, branch.id, order.id, "resend")
    assert %{status: "pending"} = Repo.reload!(order).crm

    assert {:error, :not_reconcilable} =
             Reconciliation.resolve(staff, branch.id, order.id, "resend")

    assert [%Event{action: "order.crm_resend_requested", actor_id: actor_id, metadata: metadata}] =
             Repo.all(from(e in Event, where: e.action == "order.crm_resend_requested"))

    assert actor_id == staff.id
    assert metadata["result"] == "queued"
  end

  test "existing CRM order is recorded with actor and result", %{
    branch: branch,
    order: order,
    staff: staff
  } do
    assert {:ok, _} = Reconciliation.resolve(staff, branch.id, order.id, "exists", "321")
    assert %{status: "sent", external_id: "321"} = Repo.reload!(order).crm

    assert [%Event{action: "order.crm_reconciled_exists", actor_id: actor_id, metadata: metadata}] =
             Repo.all(from(e in Event, where: e.action == "order.crm_reconciled_exists"))

    assert actor_id == staff.id
    assert metadata["result"] == "confirmed_existing"
  end

  test "blank CRM numbers and terminal orders cannot be reconciled", %{
    branch: branch,
    order: order,
    staff: staff
  } do
    assert {:error, :number_required} =
             Reconciliation.resolve(staff, branch.id, order.id, "exists", "   ")

    for status <- [:cancelled, :completed] do
      Repo.update!(Ecto.Changeset.change(order, status: status))

      assert {:error, :not_reconcilable} =
               Reconciliation.resolve(staff, branch.id, order.id, "resend")
    end

    assert Repo.all(from(e in Event, where: e.action == "order.crm_resend_requested")) == []
  end

  test "branch and permission guards remain in force", %{branch: branch, order: order} do
    outsider = insert(:staff, role: insert(:role, permissions: ["orders.update"]))
    assert {:error, :forbidden} = Reconciliation.resolve(outsider, branch.id, order.id, "resend")

    other = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["orders.update"]), branches: [other])

    assert {:error, :order_not_found} =
             Reconciliation.resolve(staff, other.id, order.id, "resend")
  end
end
