defmodule Delivest.SegmentsPaginationTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory
  import Ecto.Query

  alias Delivest.{Features, OrderFixtures, Repo, Segments}
  alias Delivest.Oms.Order
  alias Delivest.Segments.Segment

  setup do
    branch = insert(:branch, is_active: true)

    staff =
      insert(:staff,
        role:
          insert(:role,
            permissions: ["segments.read", "segments.manage", "segments.network"]
          )
      )

    Repo.insert!(%Delivest.Identity.StaffBranch{staff_id: staff.id, branch_id: branch.id})
    {:ok, _} = Features.configure("segments", :franchise, true, actor: "test")
    {:ok, _} = Features.configure("segments", {:branch, branch.id}, true, actor: "test")
    %{branch: branch, staff: staff}
  end

  test "segment list cursor exists only when another visible page exists", %{staff: staff} do
    assert {:ok, %{entries: [], next_cursor: nil}} = Segments.list_page(staff)

    insert_list_segments(1)
    assert {:ok, %{entries: [_], next_cursor: nil}} = Segments.list_page(staff)

    insert_list_segments(49)
    assert {:ok, %{entries: exact, next_cursor: nil}} = Segments.list_page(staff)
    assert length(exact) == 50
    assert {:ok, legacy} = Segments.list(staff)
    assert Enum.map(legacy, & &1.id) == Enum.map(exact, & &1.id)

    insert_list_segments(1)
    assert {:ok, %{entries: first, next_cursor: cursor}} = Segments.list_page(staff)
    assert length(first) == 50 and cursor == List.last(first).id
    assert {:ok, %{entries: [last], next_cursor: nil}} = Segments.list_page(staff, after: cursor)
    refute last.id in Enum.map(first, & &1.id)
    assert {:ok, %{entries: [], next_cursor: nil}} = Segments.list_page(staff, after: last.id)
    assert {:error, :invalid_limit} = Segments.list_page(staff, limit: 51)
  end

  test "cursor ignores forbidden rows between allowed branch segments", %{branch: branch} do
    other = insert(:branch, is_active: true)
    {:ok, _} = Features.configure("segments", {:branch, other.id}, true, actor: "test")
    viewer = insert(:staff, role: insert(:role, permissions: ["segments.read"]))
    Repo.insert!(%Delivest.Identity.StaffBranch{staff_id: viewer.id, branch_id: branch.id})

    [first, hidden, last] =
      for index <- 1..3 do
        Repo.insert!(%Segment{name: "Scoped #{index}", kind: :manual, scope: :branches})
      end
      |> Enum.sort_by(& &1.id)

    for {segment, branch_id} <- [{first, branch.id}, {hidden, other.id}, {last, branch.id}] do
      Repo.insert_all("segment_branches", [
        %{
          segment_id: Ecto.UUID.dump!(segment.id),
          branch_id: Ecto.UUID.dump!(branch_id)
        }
      ])
    end

    assert {:ok, %{entries: [listed], next_cursor: cursor}} =
             Segments.list_page(viewer, limit: 1)

    assert listed.id == first.id and cursor == first.id

    assert {:ok, %{entries: [listed], next_cursor: nil}} =
             Segments.list_page(viewer, limit: 1, after: cursor)

    assert listed.id == last.id
    assert {:ok, [legacy]} = Segments.list(viewer, limit: 1)
    assert legacy.id == first.id
  end

  defp insert_list_segments(count) do
    for index <- 1..count do
      Repo.insert!(%Segment{
        name: "Listed #{index}-#{System.unique_integer([:positive])}",
        kind: :manual,
        scope: :franchise
      })
    end
  end

  test "members have fixed pages of 20, stable sorting, search and page clamping", %{
    staff: staff
  } do
    {:ok, segment} =
      Segments.create(staff, %{name: "Many", kind: :manual, scope: :franchise})

    clients = for index <- 1..45, do: insert(:client, name: "Name #{rem(index, 3)}")
    insert_members(segment, clients)

    assert {:ok, first} =
             Segments.paginated_clients(staff, segment.id, %{"page_size" => "100"})

    assert %{page: 1, page_size: 20, total_pages: 3, total_count: 45} = first
    assert length(first.clients) == 20
    assert {:ok, second} = Segments.paginated_clients(staff, segment.id, %{"page" => "2"})
    assert {:ok, third} = Segments.paginated_clients(staff, segment.id, %{"page" => "3"})
    assert length(second.clients) == 20 and length(third.clients) == 5

    expected = clients |> Enum.sort_by(&{&1.name, &1.id}) |> Enum.map(& &1.id)
    actual = (first.clients ++ second.clients ++ third.clients) |> Enum.map(& &1.id)
    assert actual == expected

    assert {:ok, by_phone} =
             Segments.paginated_clients(staff, segment.id, %{
               "sort" => "phone",
               "direction" => "desc"
             })

    assert Enum.map(by_phone.clients, & &1.id) ==
             clients
             |> Enum.sort_by(& &1.phone, :desc)
             |> Enum.take(20)
             |> Enum.map(& &1.id)

    assert {:ok, searched} =
             Segments.paginated_clients(staff, segment.id, %{"search" => "Name 1"})

    assert searched.total_count == 15
    assert Enum.all?(searched.clients, &(&1.name == "Name 1"))

    assert {:ok, last} =
             Segments.paginated_clients(staff, segment.id, %{"page" => "999999"})

    assert last.page == 3 and length(last.clients) == 5

    remove_member(segment, hd(third.clients))
    assert {:ok, clamped} = Segments.paginated_clients(staff, segment.id, %{"page" => "999999"})
    assert clamped.page == 3 and clamped.total_count == 44
    assert length(clamped.clients) == 4

    assert {:ok, normalized} =
             Segments.paginated_clients(staff, segment.id, %{
               "page" => "bad",
               "sort" => "id",
               "direction" => "sideways"
             })

    assert normalized.page == 1 and normalized.sort == "name"
    assert normalized.direction == "asc"

    assert {:error, :invalid_search} =
             Segments.paginated_clients(staff, segment.id, %{
               "search" => %{"unexpected" => "value"}
             })

    assert {:error, :invalid_search} =
             Segments.paginated_clients(staff, segment.id, %{
               "search" => String.duplicate("a", 101)
             })
  end

  test "available mode excludes all members before applying the page limit", %{staff: staff} do
    {:ok, segment} =
      Segments.create(staff, %{name: "Candidates", kind: :manual, scope: :franchise})

    clients = for _ <- 1..23, do: insert(:client, name: "Candidate")
    members = clients |> Enum.sort_by(& &1.id) |> Enum.take(20)
    insert_members(segment, members)
    blocked = insert(:client, name: "Candidate", status: :blocked)
    deleted = insert(:client, name: "Candidate", deleted_at: DateTime.utc_now(:second))

    assert {:ok, result} =
             Segments.paginated_clients(staff, segment.id, %{
               "mode" => "available",
               "search" => "Candidate"
             })

    assert result.total_count == 3 and result.page_size == 20

    assert MapSet.new(Enum.map(result.clients, & &1.id)) ==
             MapSet.new(Enum.map(clients -- members, & &1.id))

    refute blocked.id in Enum.map(result.clients, & &1.id)
    refute deleted.id in Enum.map(result.clients, & &1.id)

    assert {:ok, escaped} =
             Segments.paginated_clients(staff, segment.id, %{
               "mode" => "available",
               "search" => "%"
             })

    assert escaped.total_count == 0
  end

  test "available mode checks manage permission and branch eligibility", %{
    staff: staff,
    branch: branch
  } do
    other_branch = insert(:branch, is_active: true)
    local = insert(:client, name: "Local")
    remote = insert(:client, name: "Remote")
    local_order = OrderFixtures.order_fixture(branch.id)
    remote_order = OrderFixtures.order_fixture(other_branch.id)
    Repo.update_all(from(o in Order, where: o.id == ^local_order.id), set: [client_id: local.id])

    Repo.update_all(from(o in Order, where: o.id == ^remote_order.id),
      set: [client_id: remote.id]
    )

    {:ok, segment} =
      Segments.create(staff, %{name: "Local", kind: :manual, scope: :branches}, [branch.id])

    assert {:ok, available} =
             Segments.paginated_clients(staff, segment.id, %{"mode" => "available"})

    assert Enum.any?(available.clients, &(&1.id == local.id))
    refute Enum.any?(available.clients, &(&1.id == remote.id))

    read_only =
      insert(:staff, role: insert(:role, permissions: ["segments.read", "segments.network"]))

    Repo.insert!(%Delivest.Identity.StaffBranch{
      staff_id: read_only.id,
      branch_id: branch.id
    })

    assert {:error, :forbidden} =
             Segments.paginated_clients(read_only, segment.id, %{"mode" => "available"})

    assert {:ok, _} = Segments.paginated_clients(read_only, segment.id)

    assert {:error, :forbidden} =
             Segments.paginated_clients(staff, segment.id, %{"mode" => "unexpected"})

    {:ok, _} = Features.configure("segments", :franchise, false, actor: "test")
    assert {:error, :not_found} = Segments.paginated_clients(staff, segment.id)
  end

  test "dynamic mode reads only the published snapshot", %{staff: staff} do
    rules = %{
      "version" => 1,
      "match" => "all",
      "conditions" => [%{"metric" => "order_count", "op" => "gte", "value" => 1}]
    }

    {:ok, segment} =
      Segments.create(staff, %{name: "Dynamic", kind: :dynamic, scope: :franchise, rules: rules})

    before = insert(:client, name: "Old snapshot")
    current = insert(:client, name: "Current snapshot")
    old_snapshot = Ecto.UUID.generate()
    snapshot = Ecto.UUID.generate()

    Repo.insert_all("segment_dynamic_members", [
      %{
        segment_id: Ecto.UUID.dump!(segment.id),
        snapshot_id: Ecto.UUID.dump!(old_snapshot),
        client_id: Ecto.UUID.dump!(before.id)
      },
      %{
        segment_id: Ecto.UUID.dump!(segment.id),
        snapshot_id: Ecto.UUID.dump!(snapshot),
        client_id: Ecto.UUID.dump!(current.id)
      }
    ])

    assert {:ok, empty} = Segments.paginated_clients(staff, segment.id)
    assert empty.total_count == 0 and empty.clients == []

    Repo.update!(Ecto.Changeset.change(segment, published_snapshot_id: snapshot))
    assert {:ok, page} = Segments.paginated_clients(staff, segment.id)
    assert page.total_count == 1 and Enum.map(page.clients, & &1.id) == [current.id]

    assert {:error, :forbidden} =
             Segments.paginated_clients(staff, segment.id, %{"mode" => "available"})
  end

  defp insert_members(segment, clients) do
    now = DateTime.utc_now(:second)

    Repo.insert_all(
      "segment_manual_members",
      Enum.map(clients, fn client ->
        %{
          segment_id: Ecto.UUID.dump!(segment.id),
          client_id: Ecto.UUID.dump!(client.id),
          inserted_at: now,
          updated_at: now
        }
      end)
    )
  end

  defp remove_member(segment, client) do
    Repo.delete_all(
      from m in "segment_manual_members",
        where:
          m.segment_id == type(^segment.id, :binary_id) and
            m.client_id == type(^client.id, :binary_id)
    )
  end
end
