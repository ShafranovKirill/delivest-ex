defmodule DelivestWeb.Staff.IntegrationLive.VkAdsTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Repo

  setup %{conn: conn} do
    branch = insert(:branch)

    editor =
      insert(:staff,
        role: insert(:role, permissions: ["integrations.read", "integrations.update"])
      )

    insert(:staff_branch, staff: editor, branch: branch)
    %{conn: init_test_session(conn, %{"staff_id" => editor.id}), branch: branch}
  end

  test "saves a branch-specific pixel in integrations", %{conn: conn, branch: branch} do
    {:ok, index, _} = live(conn, ~p"/staff/b/#{branch}/integrations")
    assert has_element?(index, "a#integration-vk-ads")
    {:ok, page, _} = live(conn, ~p"/staff/b/#{branch}/integrations/vk-ads")

    page
    |> form("#vk-ads-settings",
      vk_ads: %{enabled: "true", counter_id: "3817108", privacy_approved: "true"}
    )
    |> render_submit()

    assert %{enabled: true, counter_id: "3817108", privacy_approved: true} =
             Repo.get_by!(BranchInfo, branch_id: branch.id).vk_ads
  end

  test "cannot enable without confirmation", %{conn: conn, branch: branch} do
    {:ok, page, _} = live(conn, ~p"/staff/b/#{branch}/integrations/vk-ads")

    page
    |> form("#vk-ads-settings", vk_ads: %{enabled: "true", counter_id: "3817108"})
    |> render_submit()

    assert is_nil(Repo.get_by(BranchInfo, branch_id: branch.id))
  end

  test "read-only staff cannot save", %{conn: conn, branch: branch} do
    reader = insert(:staff, role: insert(:role, permissions: ["integrations.read"]))
    insert(:staff_branch, staff: reader, branch: branch)
    conn = init_test_session(conn, %{"staff_id" => reader.id})
    {:ok, page, _} = live(conn, ~p"/staff/b/#{branch}/integrations/vk-ads")
    refute has_element?(page, "button[form='vk-ads-settings']")

    page
    |> element("#vk-ads-settings")
    |> render_submit(%{
      "vk_ads" => %{"enabled" => "true", "counter_id" => "12345", "privacy_approved" => "true"}
    })

    assert is_nil(Repo.get_by(BranchInfo, branch_id: branch.id))
  end

  test "inaccessible branch cannot be opened", %{conn: conn} do
    foreign = insert(:branch)

    assert {:error, {:redirect, %{to: "/staff/branches/select"}}} =
             live(conn, ~p"/staff/b/#{foreign}/integrations/vk-ads")
  end
end
