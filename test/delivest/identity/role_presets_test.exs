defmodule Delivest.Identity.RolePresetsTest do
  use Delivest.DataCase, async: true

  alias Delivest.Identity.{Definitions, RolePresets}

  test "presets are created once and only the admin role is full access" do
    assert Enum.all?(RolePresets.seed(), &match?({:created, _}, &1))
    assert Enum.all?(RolePresets.seed(), &match?({:exists, _}, &1))

    assert %{permissions: ["admin"]} = RolePresets.admin_role()

    for %{permissions: permissions} <- tl(RolePresets.all()) do
      assert permissions -- Definitions.grantable() == []
    end
  end
end
