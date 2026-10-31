defmodule DelivestWeb.Staff.IntegrationLive.FiscalTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Fiscal
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Repo

  setup %{conn: conn} do
    branch = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id})

    staff =
      insert(:staff,
        role: insert(:role, permissions: ["integrations.read", "integrations.update"])
      )

    insert(:staff_branch, staff: staff, branch: branch)
    %{conn: init_test_session(conn, %{"staff_id" => staff.id}), branch: branch, staff: staff}
  end

  test "turns on our receipts and keeps the password", %{conn: conn, branch: branch} do
    {:ok, lv, _html} = live(conn, ~p"/staff/b/#{branch}/integrations/fiscal")

    lv |> form("#fiscal-settings", fiscal: %{mode: "own"}) |> render_change()

    lv
    |> form("#fiscal-settings",
      fiscal: %{
        mode: "own",
        inn: "5544332219",
        sno: "usn_income",
        payment_address: "https://v5.online.atol.ru",
        email: "chek@pizza.ru",
        delivery_vat: "vat20",
        atol: %{login: "l", password: "p", group_code: "g", sandbox: "true"}
      }
    )
    |> render_submit()

    assert %{mode: :own, delivery_vat: :vat20, atol: %{password: "p", callback_token: token}} =
             Fiscal.settings(branch.id)

    assert is_binary(token)

    lv
    |> form("#fiscal-settings", fiscal: %{mode: "own", atol: %{login: "l2", password: ""}})
    |> render_submit()

    assert %{atol: %{login: "l2", password: "p", callback_token: ^token}} =
             Fiscal.settings(branch.id)
  end

  test "requires the legal details for our receipts", %{staff: staff, branch: branch} do
    staff = Repo.preload(staff, [:role, :branches])
    result = Fiscal.update_settings(staff, branch.id, %{"mode" => "own", "inn" => ""})
    assert {:error, %Ecto.Changeset{} = changeset} = result
    assert %{inn: ["can't be blank"]} = Delivest.DataCase.errors_on(changeset)
    assert %{mode: :off} = Fiscal.settings(branch.id)
  end
end
