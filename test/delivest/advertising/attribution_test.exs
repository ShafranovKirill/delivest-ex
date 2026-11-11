defmodule Delivest.Advertising.AttributionTest do
  use Delivest.DataCase, async: false
  import Delivest.Factory

  alias Delivest.{Features, Repo}
  alias Delivest.Advertising.{Attribution, Click, Clicks, GuestClaim, Links}

  defp enable(branch) do
    {:ok, _} = Features.configure("analytics_links", :franchise, true, actor: "host")
    {:ok, _} = Features.configure("analytics_links", {:branch, branch.id}, true, actor: "host")
  end

  defp link(branch, campaign) do
    staff = insert(:staff, role: insert(:role, permissions: ["statistics.read"]))
    insert(:staff_branch, staff: staff, branch: branch)

    {:ok, link} =
      Links.create(Repo.preload(staff, [:role, :branches]), branch.id, %{
        "campaign" => campaign,
        "name" => campaign
      })

    link
  end

  defp click(link, guest_id, at) do
    id = Ecto.UUID.generate()

    Repo.insert_all(Click, [
      %{id: id, link_id: link.id, branch_id: link.branch_id, guest_id: guest_id, clicked_at: at}
    ])

    Repo.get!(Click, id)
  end

  test "last touch is bounded, ordered and ignores unverified funnel labels" do
    branch = insert(:branch, is_active: true)
    enable(branch)
    first = link(branch, "first")
    last = link(branch, "last")
    guest = Ecto.UUID.generate()
    as_of = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    click(first, guest, DateTime.add(as_of, -7 * 86_400, :second))
    click(last, guest, DateTime.add(as_of, -1, :second))
    future = click(first, guest, DateTime.add(as_of, 1, :second))

    selected = Attribution.last_touch(nil, guest, as_of)
    assert selected.link_id == last.id
    refute selected.id == future.id
    assert Attribution.last_touch(nil, Ecto.UUID.generate(), as_of) == nil
  end

  test "first observed source is immutable across later clicks and raw pruning" do
    branch = insert(:branch, is_active: true)
    enable(branch)
    first = link(branch, "first")
    later = link(branch, "later")
    guest = Ecto.UUID.generate()
    client = insert(:client)
    second_client = insert(:client)
    old = DateTime.add(DateTime.utc_now(), -89 * 86_400, :second)
    click(first, guest, old)
    click(later, guest, DateTime.add(old, 1, :second))

    assert {:ok, %{claimed: 1}} = Attribution.claim(client.id, guest)
    assert Repo.aggregate(Click, :count) == 2
    assert Repo.aggregate(GuestClaim, :count) == 1
    assert Attribution.first_source(client.id).link_id == first.id

    assert Attribution.last_touch(client.id, nil, DateTime.add(old, 2, :second)).link_id ==
             later.id

    assert {:ok, %{claimed: 0}} = Attribution.claim(second_client.id, guest)
    assert Attribution.first_source(second_client.id) == nil
    assert Attribution.last_touch(second_client.id, guest) == nil
    assert Clicks.prune(DateTime.add(DateTime.utc_now(), 2 * 86_400, :second)) == 2
    assert Clicks.prune_claims(DateTime.add(DateTime.utc_now(), 91 * 86_400, :second)) == 1
    assert Attribution.first_source(client.id).link_id == first.id
  end

  test "expired unpruned click cannot establish a new first source" do
    branch = insert(:branch, is_active: true)
    enable(branch)
    expired = link(branch, "expired")
    fresh = link(branch, "fresh")
    guest = Ecto.UUID.generate()
    client = insert(:client)
    click(expired, guest, DateTime.add(DateTime.utc_now(), -91 * 86_400, :second))
    click(fresh, guest, DateTime.add(DateTime.utc_now(), -1, :second))

    assert {:ok, %{claimed: 1}} = Attribution.claim(client.id, guest)
    assert Attribution.first_source(client.id).link_id == fresh.id
  end

  test "microsecond cutoff accepts prior same-second hit and excludes future hit" do
    branch = insert(:branch, is_active: true)
    enable(branch)
    first = link(branch, "prior")
    future = link(branch, "future")
    guest = Ecto.UUID.generate()
    second = DateTime.utc_now() |> DateTime.truncate(:second)
    before = %{second | microsecond: {400_000, 6}}
    as_of = %{second | microsecond: {500_000, 6}}
    after_cutoff = %{second | microsecond: {600_000, 6}}
    click(first, guest, before)
    click(future, guest, after_cutoff)
    assert Attribution.last_touch(nil, guest, as_of).link_id == first.id
  end
end
