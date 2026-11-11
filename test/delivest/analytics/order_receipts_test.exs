defmodule Delivest.Analytics.OrderReceiptsTest do
  use Delivest.DataCase, async: false
  import Delivest.Factory

  alias Delivest.{Features, Funnel, Repo}

  alias Delivest.Advertising.{
    Attribution,
    Click,
    FirstSource,
    GuestClaim,
    Links,
    OrderAttribution
  }

  alias Delivest.Funnel.OrderReceipt
  alias Delivest.Funnel.OrderCapture, as: FunnelOrderCapture
  alias Delivest.Oms.{Carts, Orders}

  defp enable(branch, feature) do
    {:ok, _} = Features.configure(feature, :franchise, true, actor: "host")
    {:ok, _} = Features.configure(feature, {:branch, branch.id}, true, actor: "host")
  end

  defp link(branch) do
    staff = insert(:staff, role: insert(:role, permissions: ["statistics.read"]))
    insert(:staff_branch, staff: staff, branch: branch)

    {:ok, link} =
      Links.create(Repo.preload(staff, [:role, :branches]), branch.id, %{
        "campaign" => "spring",
        "name" => "Spring"
      })

    link
  end

  defp click(link, guest, at) do
    Repo.insert_all(Click, [
      %{
        id: Ecto.UUID.generate(),
        link_id: link.id,
        branch_id: link.branch_id,
        guest_id: guest,
        clicked_at: at
      }
    ])
  end

  defp checkout(branch, opts) do
    product = insert_branch_product(branch.id, price: 300)
    {:ok, cart} = Carts.create_cart(%{session_id: Ecto.UUID.generate(), branch_id: branch.id})
    {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)

    attrs = %{
      "cart_id" => cart.id,
      "branch_id" => branch.id,
      "fulfillment_type" => "pickup",
      "payment_method" => "cash"
    }

    {attrs, Orders.create_order(attrs, opts)}
  end

  test "core transaction fixes ad and funnel receipts independently and replay cannot rewrite them" do
    branch = insert(:branch, is_active: true)
    enable(branch, "analytics_links")
    enable(branch, "analytics_funnel")
    link = link(branch)
    guest = Ecto.UUID.generate()
    click(link, guest, DateTime.utc_now() |> DateTime.truncate(:microsecond))

    assert {:ok, _} =
             Funnel.capture(
               %{
                 "event_id" => Ecto.UUID.generate(),
                 "branch_id" => branch.id,
                 "event" => "visit",
                 "source_type" => "campaign",
                 "utm_source" => "unverified"
               },
               "guest:" <> guest
             )

    key = Ecto.UUID.generate()

    opts = [
      analytics_guest_id: guest,
      idempotency: %{owner: "guest:test", key: key, fingerprint: "fixed"}
    ]

    {attrs, {:ok, order}} = checkout(branch, opts)
    receipt = Repo.get!(OrderAttribution, order.id)
    assert receipt.link_id == link.id
    assert DateTime.compare(receipt.clicked_at, receipt.as_of_at) in [:lt, :eq]

    assert %OrderReceipt{source_type: "campaign", utm_source: "unverified"} =
             Repo.get!(OrderReceipt, order.id)

    click(link, guest, DateTime.add(receipt.as_of_at, 1, :second))
    assert {:ok, replayed, :replay} = Orders.create_order(attrs, opts)
    assert replayed.id == order.id
    assert Repo.get!(OrderAttribution, order.id).clicked_at == receipt.clicked_at
    assert Repo.aggregate(OrderAttribution, :count) == 1
  end

  test "off gates write no optional receipts" do
    branch = insert(:branch, is_active: true)
    {_attrs, {:ok, order}} = checkout(branch, analytics_guest_id: Ecto.UUID.generate())
    assert Repo.get(OrderAttribution, order.id) == nil
    assert Repo.get(OrderReceipt, order.id) == nil
  end

  test "online awaiting-payment order records both receipts before payment completion" do
    branch = insert(:branch, is_active: true)
    enable(branch, "analytics_links")
    enable(branch, "analytics_funnel")
    link = link(branch)
    guest = Ecto.UUID.generate()
    click(link, guest, DateTime.utc_now() |> DateTime.truncate(:microsecond))

    assert {:ok, _} =
             Funnel.capture(
               %{
                 "event_id" => Ecto.UUID.generate(),
                 "branch_id" => branch.id,
                 "event" => "visit",
                 "source_type" => "campaign",
                 "utm_source" => "online"
               },
               "guest:" <> guest
             )

    {_attrs, {:ok, order}} = checkout(branch, analytics_guest_id: guest, online: true)
    assert order.awaiting_payment
    assert order.status == :created
    assert %OrderAttribution{link_id: link_id} = Repo.get(OrderAttribution, order.id)
    assert link_id == link.id
    assert %OrderReceipt{utm_source: "online"} = Repo.get(OrderReceipt, order.id)
  end

  test "disabled analytics links leaves funnel receipt but no attribution" do
    branch = insert(:branch, is_active: true)
    enable(branch, "analytics_funnel")
    guest = Ecto.UUID.generate()

    assert {:ok, _} =
             Funnel.capture(
               %{
                 "event_id" => Ecto.UUID.generate(),
                 "branch_id" => branch.id,
                 "event" => "visit"
               },
               "guest:" <> guest
             )

    {_attrs, {:ok, order}} = checkout(branch, analytics_guest_id: guest)
    assert Repo.get(OrderAttribution, order.id) == nil
    assert %OrderReceipt{owner_kind: "guest"} = Repo.get(OrderReceipt, order.id)
  end

  test "phone-resolved guest order does not claim verified client first source" do
    branch = insert(:branch, is_active: true)
    enable(branch, "analytics_links")
    link = link(branch)
    guest = Ecto.UUID.generate()
    click(link, guest, DateTime.utc_now() |> DateTime.truncate(:microsecond))

    product = insert_branch_product(branch.id, price: 300)
    {:ok, cart} = Carts.create_cart(%{session_id: Ecto.UUID.generate(), branch_id: branch.id})
    {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)

    assert {:ok, order} =
             Orders.create_order(
               %{
                 "cart_id" => cart.id,
                 "branch_id" => branch.id,
                 "fulfillment_type" => "pickup",
                 "payment_method" => "cash",
                 "customer_phone" => "+79991234567"
               },
               analytics_guest_id: guest
             )

    assert order.client_id
    assert %OrderAttribution{link_id: link_id} = Repo.get(OrderAttribution, order.id)
    assert link_id == link.id
    assert Repo.get(FirstSource, order.client_id) == nil
    assert Repo.get(GuestClaim, guest) == nil
  end

  test "seven-day edge includes recent click and excludes older and future clicks" do
    branch = insert(:branch, is_active: true)
    enable(branch, "analytics_links")
    link = link(branch)
    guest = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    click(link, guest, DateTime.add(now, -7 * 86_400 - 2, :second))
    click(link, guest, DateTime.add(now, -7 * 86_400 + 2, :second))
    click(link, guest, DateTime.add(now, 60, :second))

    {attrs, {:ok, order}} =
      checkout(branch,
        analytics_guest_id: guest,
        idempotency: %{owner: "guest:edge", key: Ecto.UUID.generate(), fingerprint: "edge"}
      )

    receipt = Repo.get!(OrderAttribution, order.id)

    assert DateTime.compare(receipt.clicked_at, DateTime.add(now, -7 * 86_400 + 2, :second)) ==
             :eq

    assert DateTime.compare(receipt.clicked_at, receipt.as_of_at) != :gt

    assert {:ok, replay, :replay} =
             Orders.create_order(attrs,
               analytics_guest_id: guest,
               idempotency: %{
                 owner: "guest:edge",
                 key: order.idempotency_key,
                 fingerprint: "edge"
               }
             )

    assert replay.id == order.id
    assert Repo.get!(OrderAttribution, order.id).clicked_at == receipt.clicked_at
  end

  test "selector includes the exact seven-day and same-second boundaries" do
    branch = insert(:branch, is_active: true)
    enable(branch, "analytics_links")
    link = link(branch)
    as_of_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(0, :microsecond)
    lower = DateTime.add(as_of_at, -7 * 86_400, :second)

    boundary_guest = Ecto.UUID.generate()
    click(link, boundary_guest, DateTime.add(lower, -1, :microsecond))
    click(link, boundary_guest, lower)
    assert Attribution.last_touch(nil, boundary_guest, as_of_at).clicked_at == lower

    same_second_guest = Ecto.UUID.generate()
    click(link, same_second_guest, as_of_at)
    click(link, same_second_guest, DateTime.add(as_of_at, 1, :microsecond))
    assert Attribution.last_touch(nil, same_second_guest, as_of_at).clicked_at == as_of_at
  end

  test "receipt keeps the last pre-cutoff event when a later event advances session last_at" do
    branch = insert(:branch, is_active: true)
    enable(branch, "analytics_funnel")
    guest = Ecto.UUID.generate()
    owner = "guest:" <> guest
    {_attrs, {:ok, order}} = checkout(branch, analytics_guest_id: guest)
    assert Repo.get(OrderReceipt, order.id) == nil

    first_event = Ecto.UUID.generate()

    assert {:ok, %{session_id: session_id}} =
             Funnel.capture(
               %{
                 "event_id" => first_event,
                 "branch_id" => branch.id,
                 "event" => "visit",
                 "source_type" => "campaign",
                 "utm_source" => "before"
               },
               owner
             )

    [[first_at]] =
      Repo.query!("SELECT received_at FROM funnel_events WHERE event_id=$1::text::uuid", [
        first_event
      ]).rows

    as_of_at = DateTime.from_naive!(first_at, "Etc/UTC")

    assert {:ok, %{session_id: ^session_id}} =
             Funnel.capture(
               %{
                 "event_id" => Ecto.UUID.generate(),
                 "branch_id" => branch.id,
                 "event" => "menu_view",
                 "source_type" => "direct"
               },
               owner
             )

    [[mutable_last_at]] =
      Repo.query!("SELECT last_at FROM funnel_sessions WHERE id=$1::text::uuid", [session_id]).rows

    assert NaiveDateTime.compare(mutable_last_at, first_at) == :gt
    assert :ok = FunnelOrderCapture.capture(order, owner, as_of_at)

    assert %OrderReceipt{
             session_id: ^session_id,
             session_last_at: ^as_of_at,
             as_of_at: ^as_of_at,
             source_type: "campaign",
             utm_source: "before"
           } = Repo.get!(OrderReceipt, order.id)
  end
end
