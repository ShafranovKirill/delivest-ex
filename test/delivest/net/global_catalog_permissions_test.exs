defmodule Delivest.Net.GlobalCatalogPermissionsTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Net.{Modifier, ModifierGroup, Modifiers, ProductTags}

  test "branch products.update cannot change installation-global catalog entries" do
    staff = insert(:staff, role: insert(:role, permissions: ["products.update"]))

    assert {:error, :forbidden} =
             Modifiers.save_group(staff, %ModifierGroup{}, %{name: "Shared"})

    assert {:error, :forbidden} =
             ProductTags.create_tag(staff, %{name: "Shared", icon: "star"})
  end

  test "explicit global capability can change installation-global catalog entries" do
    staff = insert(:staff, role: insert(:role, permissions: ["catalog.global.manage"]))

    assert {:ok, %ModifierGroup{name: "Shared"}} =
             Modifiers.save_group(staff, %ModifierGroup{}, %{name: "Shared"})
  end

  test "modifier CRM IDs change only for the requested branch" do
    staff = insert(:staff, role: insert(:role, permissions: ["products.update"]))
    [a, b] = for _ <- 1..2, do: insert(:branch)
    for branch <- [a, b], do: insert(:staff_branch, staff: staff, branch: branch)
    group = Repo.insert!(%ModifierGroup{name: "Shared"})
    modifier = Repo.insert!(%Modifier{group_id: group.id, name: "Extra"})

    assert {:ok, _} = Modifiers.put_crm_id(staff, modifier, a.id, :frontpad, "A")
    assert {:ok, _} = Modifiers.put_crm_id(staff, modifier, b.id, :frontpad, "B")
    assert Modifiers.crm_ids([modifier.id], :frontpad, a.id) == %{modifier.id => "A"}
    assert Modifiers.crm_ids([modifier.id], :frontpad, b.id) == %{modifier.id => "B"}

    assert {:ok, nil} = Modifiers.put_crm_id(staff, modifier, b.id, :frontpad, "")
    assert Modifiers.crm_ids([modifier.id], :frontpad, a.id) == %{modifier.id => "A"}
    assert Modifiers.crm_ids([modifier.id], :frontpad, b.id) == %{}
  end
end
