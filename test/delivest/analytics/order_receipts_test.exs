defmodule Delivest.Analytics.OrderReceiptsTest do
  use Delivest.DataCase, async: false
  import Delivest.Factory

  alias Delivest.{Features, Funnel, Repo}
  alias Delivest.Advertising.{Click, Links, OrderAttribution}
  alias Delivest.Funnel.OrderReceipt
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
end
