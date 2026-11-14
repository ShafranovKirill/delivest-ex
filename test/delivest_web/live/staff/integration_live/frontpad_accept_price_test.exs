defmodule DelivestWeb.Staff.IntegrationLive.FrontpadAcceptPriceTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Integrations.Crm.{BranchSettings, Catalog}
  alias Delivest.Integrations.Frontpad
  alias DelivestWeb.Staff.IntegrationLive.Frontpad, as: FrontpadLive

  defp setup_branch(conn, shared? \\ false) do
    branch = insert(:branch)

    Delivest.Repo.insert!(%Delivest.Identity.Branch.BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Frontpad.Settings{api_key: "ui-#{branch.id}"}
      }
    })

    product = insert_branch_product(branch.id, external_id: "42", price: 60_000)

    if shared? do
      other = insert(:branch)

      {:ok, _} =
        Delivest.Relations.create_relation(
          Delivest.Repo,
          "Branch",
          other.id,
          "Product",
          product.id
        )
    end

    staff =
      insert(:staff, role: insert(:role, permissions: ["products.update", "integrations.read"]))

    insert(:staff_branch, staff: staff, branch: branch)
    catalog("650")
    {:ok, _} = Catalog.refresh(branch.id, :frontpad)
    conn = init_test_session(conn, %{"staff_id" => staff.id})
    {conn, branch, product}
  end

  defp catalog(price) do
    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{
        "result" => "success",
        "product_id" => %{"0" => "42"},
        "name" => %{"0" => "Soup"},
        "price" => %{"0" => price}
      })
    end)
  end

  test "one CTA accepts the fresh price and clears the mismatch", %{conn: conn} do
    {conn, branch, product} = setup_branch(conn)
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/integrations/frontpad")
    assert has_element?(view, "#frontpad-accept-price-#{product.id}")

    element(view, "#frontpad-accept-price-#{product.id}") |> render_click()
    render_async(view)
    refute has_element?(view, "#frontpad-accept-price-#{product.id}")
    assert Delivest.Repo.get!(Delivest.Net.Product, product.id).price == 65_000
  end

  test "Russian locale shows the accept price action", %{conn: conn} do
    {conn, branch, product} = setup_branch(conn)
    conn = put_session(conn, "locale", "ru")
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/integrations/frontpad")

    assert has_element?(
             view,
             "#frontpad-accept-price-#{product.id}",
             "Принять цену из CRM"
           )
  end

  test "forged browser price is ignored and the shown server price is accepted", %{conn: conn} do
    {conn, branch, product} = setup_branch(conn)
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/integrations/frontpad")
    Req.Test.stub(Delivest.HTTP.Client, fn _ -> flunk("accept must not call CRM") end)
    render_click(view, "accept_price", %{"product_id" => product.id, "crm_price" => "999999"})
    render_async(view)
    assert Delivest.Repo.get!(Delivest.Net.Product, product.id).price == 65_000
    refute has_element?(view, "#frontpad-accept-price-#{product.id}")
    refute has_element?(view, "#frontpad-price-mismatch")
  end

  test "shared product explains why the CTA is unavailable", %{conn: conn} do
    {conn, branch, product} = setup_branch(conn, true)
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/integrations/frontpad")
    assert has_element?(view, "#frontpad-accept-price-#{product.id}[disabled]")
    assert has_element?(view, "#frontpad-price-mismatch", "Shared product")
  end

  test "provider outage does not prevent accepting the displayed price", %{conn: conn} do
    {conn, branch, product} = setup_branch(conn)
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/integrations/frontpad")

    Req.Test.stub(Delivest.HTTP.Client, fn _ -> flunk("accept must not call CRM") end)

    element(view, "#frontpad-accept-price-#{product.id}") |> render_click()
    render_async(view)
    refute has_element?(view, "#frontpad-accept-price-#{product.id}")
    assert Delivest.Repo.get!(Delivest.Net.Product, product.id).price == 65_000
  end

  test "unexpected task exit reconciles the stored price before reporting success", %{conn: conn} do
    {_conn, branch, product} = setup_branch(conn)

    staff =
      insert(:staff, role: insert(:role, permissions: ["products.update", "integrations.read"]))

    insert(:staff_branch, staff: staff, branch: branch)

    socket = fn ->
      %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          current_branch: branch,
          current_staff: staff,
          accepting_price_value: 65_000,
          refresh_timer: nil,
          flash: %{}
        }
      }
    end

    {:noreply, unchanged} =
      FrontpadLive.handle_async({:accept_price, product.id}, {:exit, :boom}, socket.())

    assert Phoenix.Flash.get(unchanged.assigns.flash, :error) =~ "Could not accept"

    assert {:ok, _} =
             Delivest.Net.Products.accept_crm_price(staff, branch.id, product.id, "42", 65_000)

    {:noreply, stored} =
      FrontpadLive.handle_async({:accept_price, product.id}, {:exit, :boom}, socket.())

    assert Phoenix.Flash.get(stored.assigns.flash, :info) =~ "Price accepted"
  end
end
