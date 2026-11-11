defmodule DelivestWeb.Staff.MarketingLive.BonusesTest do
  use DelivestWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.{Franchise, Repo}
  alias Delivest.Identity.Branch.BranchInfo

  setup %{conn: conn} do
    Cachex.clear(:franchise_cache)
    branch = insert(:branch)
    other = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id})
    Repo.insert!(%BranchInfo{branch_id: other.id})
    %{conn: conn, branch: branch, other: other}
  end

  test "franchise manager saves shared rates without a selected branch", %{
    conn: conn,
    branch: branch
  } do
    staff = insert(:staff, role: insert(:role, permissions: ["franchise.update"]))
    assert {:ok, _} = Franchise.update_settings(staff, %{name: "Persistent brand"})
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, lv, _} = live(conn, ~p"/staff/marketing/bonuses")
    assert has_element?(lv, "#common-bonuses-form")
    refute has_element?(lv, "#bonus-branch-#{branch.id}")

    lv
    |> form("#common-bonuses-form",
      settings: %{loyalty_per_rubles: "200", loyalty_stars: "12", loyalty_expire_days: "45"}
    )
    |> render_submit()

    assert %{
             name: "Persistent brand",
             loyalty_per_rubles: 200,
             loyalty_stars: 12,
             loyalty_expire_days: 45
           } =
             Franchise.get_settings()

    assert has_element?(
             lv,
             ~s(#common-bonuses-form input[name="settings[loyalty_stars]"][value="12"])
           )
  end

  test "branch manager sees only permitted branches and cannot see shared form", %{
    conn: conn,
    branch: branch,
    other: other
  } do
    staff = insert(:staff, role: insert(:role, permissions: ["promotions.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    {:ok, lv, _} = live(conn, ~p"/staff/marketing/bonuses")
    assert has_element?(lv, "#bonus-branch-#{branch.id}")
    refute has_element?(lv, "#bonus-branch-#{other.id}")
    refute has_element?(lv, "#common-bonuses-form")
  end

  test "a staff member without either permission cannot open bonuses", %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: []))
    conn = init_test_session(conn, %{"staff_id" => staff.id})

    assert {:error, {:redirect, %{to: "/staff/branches/select"}}} =
             live(conn, ~p"/staff/marketing/bonuses")
  end
end
