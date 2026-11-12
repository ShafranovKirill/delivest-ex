defmodule Delivest.PopularTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.{Popular, Repo}

  test "display settings reject null flags and keep compatibility defaults" do
    settings = %Delivest.Popular.Settings{}
    assert settings.show_in_menu == false
    assert settings.show_in_cart == true

    changeset = Popular.change_settings(settings, %{show_in_menu: nil, show_in_cart: nil})
    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :show_in_menu)
    assert Keyword.has_key?(changeset.errors, :show_in_cart)
  end

  test "manual mode returns the picked products in order" do
    branch = insert(:branch)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    first = insert_branch_product(branch.id, name: "Первый")
    second = insert_branch_product(branch.id, name: "Второй")

    {:ok, _} = Popular.update_settings(admin, branch.id, %{"mode" => "manual"})
    {:ok, _} = Popular.add_product(admin, branch.id, first.id)
    {:ok, _} = Popular.add_product(admin, branch.id, second.id)

    assert Enum.map(Popular.list_products(branch.id), & &1.id) == [first.id, second.id]

    {:ok, _} = Popular.reorder(admin, branch.id, [second.id, first.id])
    assert Enum.map(Popular.list_products(branch.id), & &1.id) == [second.id, first.id]

    {:ok, _} = Popular.remove_product(admin, branch.id, second.id)
    assert Enum.map(Popular.list_products(branch.id), & &1.id) == [first.id]
  end

  test "bulk replacement is atomic and rejects foreign branch products" do
    branch = insert(:branch)
    other = insert(:branch)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    first = insert_branch_product(branch.id)
    foreign = insert_branch_product(other.id)

    assert {:ok, _} = Popular.replace_products(admin, branch.id, [first.id])
    assert {:error, :invalid_products} = Popular.replace_products(admin, branch.id, [foreign.id])
    assert Popular.list_product_ids(branch.id) == [first.id]
  end

  test "off mode hides the popular list but keeps the picked products" do
    branch = insert(:branch)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    product = insert_branch_product(branch.id)

    {:ok, _} = Popular.update_settings(admin, branch.id, %{"mode" => "manual"})
    {:ok, _} = Popular.add_product(admin, branch.id, product.id)

    assert [%{id: id}] = Popular.list_products(branch.id)
    assert id == product.id

    {:ok, _} = Popular.update_settings(admin, branch.id, %{"mode" => "off"})
    assert Popular.list_products(branch.id) == []
    assert Popular.list_product_ids(branch.id) == [product.id]
  end

  test "auto mode picks the best-selling products of the branch" do
    branch = insert(:branch)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    product = insert_branch_product(branch.id)

    {:ok, _} = Popular.update_settings(admin, branch.id, %{"mode" => "auto", "auto_limit" => 3})

    assert Popular.list_products(branch.id) == []

    cart = Repo.insert!(%Delivest.Oms.Cart{branch_id: branch.id, fulfillment_type: "pickup"})

    order =
      Repo.insert!(%Delivest.Oms.Order{
        number: "1",
        daily_number: 1,
        business_date: Date.utc_today(),
        branch_id: branch.id,
        cart_id: cart.id,
        status: :completed,
        fulfillment_type: :pickup,
        payment_method: :cash
      })

    Repo.insert!(%Delivest.Oms.OrderItem{
      order_id: order.id,
      product_id: product.id,
      title: product.name,
      price: 100,
      quantity: 5
    })

    assert Popular.list_products(branch.id) == []
    {:ok, _} = Popular.recalculate(admin, branch.id)
    assert Enum.map(Popular.list_products(branch.id), & &1.id) == [product.id]
    assert Popular.get_settings(branch.id).auto_product_ids == [product.id]
    assert Popular.get_settings(branch.id).calculated_at
  end

  test "daily refresh is due only for enabled auto settings after local 03:00" do
    branch = insert(:branch)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    {:ok, settings} = Popular.update_settings(admin, branch.id, %{"mode" => "auto"})
    settings = %{settings | calculated_at: DateTime.add(DateTime.utc_now(), -86_400)}

    zone = Delivest.LocalTime.timezone(branch.id)
    today = Delivest.LocalTime.today(zone)
    before = Delivest.LocalTime.naive_to_utc(NaiveDateTime.new!(today, ~T[02:59:00]), zone)
    after_time = Delivest.LocalTime.naive_to_utc(NaiveDateTime.new!(today, ~T[03:01:00]), zone)

    refute Delivest.Popular.RefreshWorker.due?(settings, before)
    assert Delivest.Popular.RefreshWorker.due?(settings, after_time)
    refute Delivest.Popular.RefreshWorker.due?(%{settings | mode: :manual}, after_time)
    refute Delivest.Popular.RefreshWorker.due?(%{settings | show_in_cart: false}, after_time)
  end

  test "daily worker refreshes enabled auto snapshots once and skips disabled branches" do
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    active = insert(:branch)
    disabled = insert(:branch)

    {:ok, active_settings} = Popular.update_settings(admin, active.id, %{"mode" => "auto"})

    {:ok, disabled_settings} =
      Popular.update_settings(admin, disabled.id, %{
        "mode" => "auto",
        "show_in_cart" => false,
        "show_in_menu" => false
      })

    Repo.update!(Ecto.Changeset.change(active_settings, calculated_at: nil))
    Repo.update!(Ecto.Changeset.change(disabled_settings, calculated_at: nil))

    assert :ok = Delivest.Popular.RefreshWorker.perform(%Oban.Job{})
    refreshed = Popular.get_settings(active.id)
    assert refreshed.calculated_at
    assert Popular.get_settings(disabled.id).calculated_at == nil

    version = Repo.get!(Delivest.Identity.Branch, active.id).catalog_version
    assert :ok = Delivest.Popular.RefreshWorker.perform(%Oban.Job{})
    assert Popular.get_settings(active.id).calculated_at == refreshed.calculated_at
    assert Repo.get!(Delivest.Identity.Branch, active.id).catalog_version == version
  end

  test "editing is forbidden without products.update" do
    branch = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["products.read"]))

    assert {:error, :forbidden} =
             Popular.update_settings(staff, branch.id, %{"mode" => "auto"})
  end
end
