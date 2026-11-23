defmodule DelivestWeb.Staff.ReceiptLive.PrintingTest do
  use DelivestWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Printing

  setup %{conn: conn} do
    Cachex.clear(:franchise_cache)
    on_exit(fn -> Cachex.clear(:franchise_cache) end)

    staff = insert(:staff, role: insert(:role, permissions: ["franchise.update"]))
    insert(:staff_branch, staff: staff, branch: insert(:branch, is_active: true))
    %{conn: init_test_session(conn, %{"staff_id" => staff.id})}
  end

  test "overview has separate cards, toggles and configure links", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/staff/franchise/printing")

    for type <- ~w(fiscal kitchen customer) do
      assert has_element?(view, "#preset-#{type}")
      assert has_element?(view, "#preset-#{type} a[href='/staff/franchise/printing/#{type}']")
    end

    refute has_element?(view, "#preview-kitchen")
    render_click(view, "toggle_enabled", %{"type" => "kitchen"})
    assert Printing.settings().kitchen_enabled
  end

  test "editor saves a two-column layout and changes the paper format", %{conn: conn} do
    first = insert(:branch)
    second = insert(:branch)
    {:ok, view, _} = live(conn, ~p"/staff/franchise/printing/kitchen")

    assert has_element?(view, "#preview-kitchen")
    render_click(view, "layout_action", %{"action" => "add_column", "row" => "0"})

    render_hook(view, "layout_reorder", %{
      "rows" => [
        [["number"], []],
        [["readiness"]],
        [["items"]],
        [["kitchen_comments"]]
      ]
    })

    view |> form("#editor-settings", %{"editor" => %{"paper" => "roll80"}}) |> render_change()
    render_click(view, "save", %{})

    for branch <- [first, second] do
      assert %{kitchen: %{paper: :roll80, layout: %{"rows" => rows}}} =
               Printing.settings(branch.id)

      assert length(hd(rows)["columns"]) == 2
    end
  end

  test "unsaved customer QR preview exports a PDF", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/staff/franchise/printing/customer")
    render_click(view, "layout_action", %{"action" => "add_block", "block" => "qr"})

    assert has_element?(view, "#preview-customer [data-id=qr] img[src^='data:image/svg+xml']")

    refute "qr" in (Printing.settings().customer || Delivest.Printing.Preset.default(:customer)).blocks

    render_click(view, "preview_pdf", %{})
    assert_push_event(view, "printing_pdf", %{base64: encoded})
    assert <<"%PDF-", _::binary>> = Base.decode64!(encoded)
  end

  test "legacy block order survives opening the editor and an invalid reorder", %{conn: conn} do
    assert {:ok, _} =
             Delivest.Franchise.SettingsStore.save(%{
               "printing" => %{"kitchen" => %{"blocks" => ["items", "number"]}}
             })

    {:ok, view, html} = live(conn, ~p"/staff/franchise/printing/kitchen")
    assert html =~ ~r/data-id="items".*data-id="number"/s
    refute has_element?(view, "#print-layout [data-id=readiness]")

    render_hook(view, "layout_reorder", %{"rows" => [[[]], [[]], [["items", "number"]]]})
    assert has_element?(view, "#print-layout [data-id=items]")
    assert has_element?(view, "#print-layout [data-id=number]")
  end

  test "fiscal chooser links to each branch", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/staff/franchise/printing/fiscal")
    assert has_element?(view, "a[href*='/integrations/fiscal']")
  end

  test "branch integration access does not grant franchise printing", %{conn: conn} do
    staff =
      insert(:staff,
        role: insert(:role, permissions: ["integrations.read", "integrations.update"])
      )

    conn = init_test_session(conn, %{"staff_id" => staff.id})
    assert {:error, {:redirect, %{to: _}}} = live(conn, ~p"/staff/franchise/printing")
  end
end
