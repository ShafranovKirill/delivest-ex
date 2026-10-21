defmodule Delivest.FranchiseTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory

  alias Delivest.Franchise

  setup do
    Cachex.clear(:franchise_cache)
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    manager = insert(:staff, role: insert(:role, permissions: ["branches.update"]))
    %{admin: admin, manager: manager}
  end

  test "returns defaults until settings are saved" do
    assert %{name: "Delivest", primary_color: "#462094"} = Franchise.get_settings()
  end

  test "only an admin updates settings and the cache follows", %{admin: admin, manager: manager} do
    assert {:error, :forbidden} = Franchise.update_settings(manager, %{"name" => "Pizza"})

    assert {:ok, _} =
             Franchise.update_settings(admin, %{"name" => "Pizza", "primary_color" => "#FF0000"})

    assert %{name: "Pizza", primary_color: "#ff0000"} = Franchise.get_settings()
  end

  test "validates color and requisites", %{admin: admin} do
    assert {:error, changeset} =
             Franchise.update_settings(admin, %{
               "primary_color" => "red",
               "inn" => "123",
               "ogrn" => "1"
             })

    assert %{primary_color: _, inn: _, ogrn: _} = errors_on(changeset)
  end

  test "documents use templates with requisites until edited", %{admin: admin} do
    {:ok, _} = Franchise.update_settings(admin, %{"legal_name" => "Вкус", "inn" => "7700000000"})

    assert %{custom: false, body: body} = Franchise.get_document(:privacy)
    assert body =~ "Вкус"
    assert body =~ "7700000000"
    refute body =~ "{{"

    {:ok, _} = Franchise.update_document(admin, :privacy, "Своя политика {{brand}} {{unknown}}")

    assert %{custom: true, body: "Своя политика Delivest {{unknown}}"} =
             Franchise.get_document(:privacy)

    {:ok, _} = Franchise.reset_document(admin, :privacy)
    assert %{custom: false} = Franchise.get_document(:privacy)
  end
end
