defmodule Delivest.PrintingTest do
  use DelivestWeb.ConnCase, async: false
  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.{Printing, Repo}
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.{Order, OrderItem}
  alias Delivest.Printing.{Preset, Settings}

  test "preset accepts an ordered subset and rejects unknown or duplicated blocks" do
    assert Preset.kitchen_changeset(Preset.default(:kitchen), %{blocks: ["items", "number"]}).valid?

    refute Preset.kitchen_changeset(Preset.default(:kitchen), %{blocks: ["items", "items"]}).valid?

    refute Preset.kitchen_changeset(Preset.default(:kitchen), %{blocks: ["contacts"]}).valid?

    assert Preset.customer_changeset(Preset.default(:customer), %{
             blocks: ["qr", "items"],
             paper: :a5,
             qr_url: "https://example.org/menu"
           }).valid?

    refute Preset.customer_changeset(Preset.default(:customer), %{blocks: ["qr"]}).valid?
    refute Preset.customer_changeset(Preset.default(:customer), %{blocks: nil}).valid?

    refute Preset.customer_changeset(Preset.default(:customer), %{qr_url: "http://localhost"}).valid?
  end

  test "kitchen document contains no customer or payment data" do
    order = %Order{
      number: "ТЕСТ-1",
      customer_phone: "+79990000000",
      total_amount: 12_300,
      comment: "Без лука",
      items: [%OrderItem{title: "Пельмени", quantity: 1, price: 12_300, modifiers: []}]
    }

    html = Printing.html(order, :kitchen, Preset.default(:kitchen))
    assert html =~ "Пельмени"
    assert html =~ "Без лука"
    refute html =~ "+79990000000"
    refute html =~ "123,00"
  end

  test "customer pricing is optional and each item appears once" do
    order = %Order{
      number: "RU-1",
      total_amount: 12_300,
      items: [
        %OrderItem{title: "Пельмени <script>", quantity: 1, price: 12_300, modifiers: []}
      ]
    }

    with_prices = Printing.html(order, :customer, %Preset{blocks: ~w(items prices)})
    without_prices = Printing.html(order, :customer, %Preset{blocks: ~w(items)})

    assert length(String.split(with_prices, "Пельмени")) == 2
    assert with_prices =~ "Итого"
    assert with_prices =~ "&lt;script&gt;"
    refute without_prices =~ "Итого"
    refute without_prices =~ "123 ₽"
  end

  test "PDF URL enforces branch permission, enabled type and valid order ID", %{conn: conn} do
    branch = insert(:branch)
    other = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["orders.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id, printing: %Settings{kitchen_enabled: true}})
    Repo.insert!(%BranchInfo{branch_id: other.id, printing: %Settings{kitchen_enabled: true}})
    own_order = order_fixture(branch.id)
    other_order = order_fixture(other.id)

    conn = init_test_session(conn, %{"staff_id" => staff.id})
    assert conn |> get(~p"/staff/b/#{branch.slug}/printing/customer/demo") |> response(404)
    assert conn |> get(~p"/staff/b/#{other.slug}/printing/kitchen/demo") |> response(404)

    assert conn
           |> get(~p"/staff/b/#{branch.slug}/printing/kitchen/#{other_order.id}")
           |> response(404)

    assert conn |> get(~p"/staff/b/#{branch.slug}/printing/kitchen/not-a-uuid") |> response(404)

    no_read = insert(:staff, role: insert(:role, permissions: ["integrations.update"]))
    insert(:staff_branch, staff: no_read, branch: branch)

    assert conn
           |> init_test_session(%{"staff_id" => no_read.id})
           |> get(~p"/staff/b/#{branch.slug}/printing/kitchen/#{own_order.id}")
           |> response(404)

    pdf_conn = get(conn, ~p"/staff/b/#{branch.slug}/printing/kitchen/#{own_order.id}")
    pdf = response(pdf_conn, 200)

    assert get_resp_header(pdf_conn, "content-type")
           |> hd()
           |> String.starts_with?("application/pdf")

    assert get_resp_header(pdf_conn, "cache-control") == ["private, no-store"]
    assert binary_part(pdf, 0, 5) == "%PDF-"

    download = get(conn, ~p"/staff/b/#{branch.slug}/printing/kitchen/#{own_order.id}?download=1")

    assert get_resp_header(download, "content-disposition") == [
             "attachment; filename=\"kitchen-ticket.pdf\""
           ]

    assert binary_part(response(download, 200), 0, 5) == "%PDF-"
  end
end
