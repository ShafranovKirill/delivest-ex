defmodule DelivestWeb.Staff.ReceiptLive.PrintingTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.{Fiscal, Printing, Repo}
  alias Delivest.Identity.Branch.BranchInfo

  setup %{conn: conn} do
    branch = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id})

    staff =
      insert(:staff,
        role: insert(:role, permissions: ["integrations.read", "integrations.update"])
      )

    insert(:staff_branch, staff: staff, branch: branch)
    %{conn: init_test_session(conn, %{"staff_id" => staff.id}), branch: branch}
  end

  test "independent toggles and ordered blocks persist in the current branch", %{
    conn: conn,
    branch: branch
  } do
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/finance/printing")
    assert has_element?(view, "#printing-settings")
    assert has_element?(view, "#preset-kitchen")
    assert has_element?(view, "#preset-customer")

    view
    |> element("#preset-kitchen button[phx-value-block='readiness'][phx-value-action='toggle']")
    |> render_click()

    view
    |> element("#preset-kitchen button[phx-value-block='items'][phx-value-action='up']")
    |> render_click()

    view
    |> form("#printing-settings", printing: %{kitchen_enabled: "true", customer_enabled: "false"})
    |> render_submit()

    assert %{kitchen_enabled: true, customer_enabled: false, kitchen: %{blocks: blocks}} =
             Printing.settings(branch.id)

    assert blocks == ~w(items number kitchen_comments)

    {:ok, reloaded, _} = live(conn, ~p"/staff/b/#{branch}/finance/printing")

    assert has_element?(
             reloaded,
             "#preset-kitchen button[phx-value-block='items'][phx-value-action='up']"
           )

    Enum.each(blocks, fn block ->
      reloaded
      |> element("#preset-kitchen button[phx-value-block='#{block}'][phx-value-action='toggle']")
      |> render_click()
    end)

    reloaded
    |> form("#printing-settings", printing: %{kitchen_enabled: "true", customer_enabled: "false"})
    |> render_submit()

    assert Printing.settings(branch.id).kitchen.blocks == []

    other = insert(:branch)
    assert Printing.settings(other.id).kitchen_enabled == false

    view |> element("#fiscal-toggle") |> render_click()
    assert Fiscal.settings(branch.id).enabled == false
    assert Printing.settings(branch.id).kitchen_enabled == true
  end

  test "read-only staff cannot forge a save command", %{conn: conn, branch: branch} do
    reader = insert(:staff, role: insert(:role, permissions: ["integrations.read"]))
    insert(:staff_branch, staff: reader, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => reader.id})

    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/finance/printing")
    refute has_element?(view, "#save-printing")
    render_submit(view, "save", %{"printing" => %{"kitchen_enabled" => "true"}})
    assert Printing.settings(branch.id).kitchen_enabled == false
  end
end
