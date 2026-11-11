defmodule DelivestWeb.Staff.IntegrationLive.FrontpadAcceptPriceTest do
  use DelivestWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Integrations.Crm.{BranchSettings, Catalog}
  alias Delivest.Integrations.Frontpad

  defp setup_branch(conn, shared? \\ false) do
    branch = insert(:branch)

    Delivest.Repo.insert!(%Delivest.Identity.Branch.BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
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

  test "changed CRM price is shown and requires another click", %{conn: conn} do
    {conn, branch, product} = setup_branch(conn)
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/integrations/frontpad")
    catalog("700")

    element(view, "#frontpad-accept-price-#{product.id}") |> render_click()
    render_async(view)
    assert has_element?(view, "#frontpad-price-#{product.id}", "700 ₽")
    assert Delivest.Repo.get!(Delivest.Net.Product, product.id).price == 60_000

    element(view, "#frontpad-accept-price-#{product.id}") |> render_click()
    render_async(view)
    assert Delivest.Repo.get!(Delivest.Net.Product, product.id).price == 70_000
    refute has_element?(view, "#frontpad-accept-price-#{product.id}")
    refute has_element?(view, "#frontpad-price-mismatch")
  end

  test "shared product explains why the CTA is unavailable", %{conn: conn} do
    {conn, branch, product} = setup_branch(conn, true)
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/integrations/frontpad")
    assert has_element?(view, "#frontpad-accept-price-#{product.id}[disabled]")
    assert has_element?(view, "#frontpad-price-mismatch", "Shared product")
  end

  test "CRM failure keeps the shown mismatch and leaves the product unchanged", %{conn: conn} do
    {conn, branch, product} = setup_branch(conn)
    {:ok, view, _} = live(conn, ~p"/staff/b/#{branch}/integrations/frontpad")

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{"result" => "error", "error" => "offline"})
    end)

    element(view, "#frontpad-accept-price-#{product.id}") |> render_click()
    render_async(view)
    assert has_element?(view, "#frontpad-accept-price-#{product.id}")
    assert has_element?(view, "#frontpad-price-#{product.id}", "650 ₽")
    assert Delivest.Repo.get!(Delivest.Net.Product, product.id).price == 60_000
  end
end
