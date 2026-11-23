defmodule Delivest.PrintingTest do
  use DelivestWeb.ConnCase, async: false
  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.{Printing, Repo}
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.{Order, OrderItem}
  alias Delivest.Printing.{Preset, Settings}

  test "order sheets print fulfillment types in Russian" do
    preset = %Preset{blocks: ["fulfillment"]}

    for {type, label} <- [delivery: "Доставка", pickup: "Самовывоз", dine_in: "В зале"] do
      html = Printing.html(%Order{fulfillment_type: type}, :customer, preset)
      assert html =~ "Тип получения: #{label}"
      refute html =~ Atom.to_string(type)
    end
  end

  test "preset accepts an ordered subset and rejects unknown or duplicated blocks" do
    assert Preset.kitchen_changeset(Preset.default(:kitchen), %{blocks: ["items", "number"]}).valid?

    refute Preset.kitchen_changeset(Preset.default(:kitchen), %{blocks: ["items", "items"]}).valid?

    refute Preset.kitchen_changeset(Preset.default(:kitchen), %{blocks: ["contacts"]}).valid?

    assert Preset.customer_changeset(Preset.default(:customer), %{
             blocks: ["qr", "items"],
             paper: :a5,
             qr_url: "https://example.org/menu"
           }).valid?

    assert Preset.customer_changeset(Preset.default(:customer), %{blocks: ["qr"]}).valid?

    refute Preset.customer_changeset(Preset.default(:customer), %{
             blocks: ["qr"],
             qr_kind: :review
           }).valid?

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

  test "legacy customer QR URLs retain their destination and purpose" do
    for {previous_kind, kind} <- [menu: :custom, feedback: :review] do
      branch = insert(:branch)
      url = "https://example.org/branch-qr"

      Repo.insert!(%BranchInfo{
        branch_id: branch.id,
        printing: %Settings{
          customer: %Preset{blocks: ["qr"], qr_kind: previous_kind, qr_url: url}
        }
      })

      assert %{customer: %{qr_kind: ^kind, qr_url: ^url}} = Printing.settings(branch.id)
    end
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

  test "layout validates widths and renders configured order fields without kitchen customer data" do
    layout = %{
      "rows" => [
        %{
          "columns" => [
            %{
              "width" => 6,
              "blocks" => [%{"type" => "number", "align" => "center", "font_size" => 18}]
            },
            %{"width" => 6, "blocks" => [%{"type" => "customer_name"}]}
          ]
        },
        %{"columns" => [%{"width" => 12, "blocks" => [%{"type" => "items"}]}]}
      ]
    }

    assert Preset.customer_changeset(Preset.default(:customer), %{layout: layout, paper: :roll58}).valid?

    refute Preset.customer_changeset(Preset.default(:customer), %{
             layout: put_in(layout, ["rows", Access.at(0), "columns", Access.at(1), "width"], 7)
           }).valid?

    refute Preset.kitchen_changeset(Preset.default(:kitchen), %{layout: layout}).valid?

    order = %Order{
      number: "RU-2",
      customer_name: "Иван",
      total_amount: 12_300,
      items: [%OrderItem{title: "Пельмени", quantity: 1, price: 12_300, modifiers: []}]
    }

    html =
      Printing.html(order, :customer, %Preset{layout: layout, blocks: ["prices"], paper: :roll58})

    assert html =~ "size:58mm 200mm"
    assert html =~ "<body data-paper=\"roll58\">"
    assert html =~ "text-align:center;font-size:18px"
    assert html =~ "Клиент: Иван"
    refute html =~ "123 ₽"

    kitchen = Printing.html(order, :kitchen, %Preset{layout: Preset.default_layout(:kitchen)})
    refute kitchen =~ "Иван"
  end

  test "long A4 item table remains pageable" do
    order = %Order{
      number: "LONG-1",
      total_amount: 0,
      items:
        for(
          n <- 1..120,
          do: %OrderItem{title: "Позиция #{n}", quantity: 1, price: 0, modifiers: []}
        )
    }

    preset = %Preset{
      layout: %{
        "rows" => [%{"columns" => [%{"width" => 12, "blocks" => [%{"type" => "items"}]}]}]
      },
      paper: :a4
    }

    html = Printing.html(order, :kitchen, preset)
    assert html =~ "<thead>"
    assert html =~ "Позиция 120"
    assert {:ok, pdf, :a4} = Printing.render(order, :kitchen, %Settings{kitchen: preset})
    assert length(Regex.scan(~r{/Type /Page\b}, pdf)) > 1
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

    html_conn = get(conn, ~p"/staff/b/#{branch.slug}/printing/kitchen/#{own_order.id}/print")
    assert response(html_conn, 200) =~ "window.print()"
    assert get_resp_header(html_conn, "cache-control") == ["private, no-store"]

    assert conn
           |> get(~p"/staff/b/#{branch.slug}/printing/kitchen/#{other_order.id}/print")
           |> response(404)
  end

  test "renderer shutdown returns 503 instead of crashing the PDF route", %{conn: conn} do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["orders.read"]))
    insert(:staff_branch, staff: staff, branch: branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id, printing: %Settings{kitchen_enabled: true}})
    order = order_fixture(branch.id)

    on_exit(fn ->
      assert {:ok, _pid} = Supervisor.restart_child(Delivest.Supervisor, ChromicPDF)
    end)

    assert :ok = Supervisor.terminate_child(Delivest.Supervisor, ChromicPDF)

    conn =
      conn
      |> init_test_session(%{"staff_id" => staff.id})
      |> get(~p"/staff/b/#{branch.slug}/printing/kitchen/#{order.id}")

    assert response(conn, 503) == ""
  end
end
