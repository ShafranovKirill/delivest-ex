defmodule DelivestWeb.Staff.AdvertisingLive.IndexTest do
  use DelivestWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.{Features, Repo}
  alias Delivest.Advertising.{Link, Links}

  defp login(conn, permissions) do
    branch = insert(:branch, is_active: true)
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    {init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id}), branch}
  end

  defp enable(branch) do
    {:ok, _} = Features.configure("analytics_links", :franchise, true, actor: "host")
    {:ok, _} = Features.configure("analytics_links", {:branch, branch.id}, true, actor: "host")
  end

  test "statistics staff can create and archive only scoped links", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])
    enable(branch)
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/advertising-links")
    assert has_element?(view, "#advertising-link-form")

    view
    |> form("#advertising-link-form", link: %{campaign: "spring", name: "Spring"})
    |> render_submit()

    assert has_element?(view, "#advertising-links input[readonly]")
    [[id]] = Repo.query!("SELECT id::text FROM advertising_links").rows
    assert has_element?(view, "#advertising-copy-#{id}")

    assert has_element?(
             view,
             "#advertising-statistics-#{id}[href*='tab=sources'][href*='link_id=#{id}']"
           )

    view |> element("#advertising-archive-#{id}") |> render_click()
    assert has_element?(view, "#advertising-links .badge", "Archived")
  end

  test "disabled gate and missing permission hide management", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])
    assert {:error, {:redirect, _}} = live(conn, ~p"/staff/b/#{branch}/advertising-links")
    enable(branch)
    {denied, denied_branch} = login(build_conn(), [])
    assert {:error, _} = live(denied, ~p"/staff/b/#{denied_branch}/advertising-links")
  end

  test "links are shown in bounded pages including archived history", %{conn: conn} do
    {conn, branch} = login(conn, ["statistics.read"])
    enable(branch)

    staff =
      Repo.preload(Repo.get!(Delivest.Identity.Staff, get_session(conn, "staff_id")), [
        :role,
        :branches
      ])

    links =
      for n <- 1..52 do
        Repo.insert!(%Link{
          branch_id: branch.id,
          token: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false),
          campaign: "page-#{n}",
          name: "Page #{n}",
          archived_at: if(n == 1, do: DateTime.utc_now())
        })
      end

    assert {:ok, %{links: first, has_more: true, next_cursor: cursor}} =
             Links.list(staff, branch.id)

    assert length(first) == 50
    assert {:ok, %{links: rest, has_more: false}} = Links.list(staff, branch.id, cursor)
    assert length(rest) == 2
    assert Enum.sort(Enum.map(first ++ rest, & &1.id)) == Enum.sort(Enum.map(links, & &1.id))

    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/advertising-links")
    assert has_element?(view, "#advertising-load-more")
    view |> element("#advertising-load-more") |> render_click()
    refute has_element?(view, "#advertising-load-more")
    assert has_element?(view, "#advertising-copy-#{hd(links).id}")

    {:ok, _} = Features.configure("analytics_links", {:branch, branch.id}, false, actor: "host")
    assert {:error, :unavailable} = Links.list(staff, branch.id)
  end
end
