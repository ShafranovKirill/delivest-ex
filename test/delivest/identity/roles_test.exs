defmodule Delivest.Identity.RoleTest do
  use Delivest.DataCase, async: true

  alias Delivest.Identity.Role
  alias Delivest.Identity.Definitions
  alias Delivest.Repo
  import Delivest.Factory

  describe "changeset/2" do
    test "should be valid with valid attributes" do
      valid_permission = Enum.at(Definitions.permissions(), 0) || "staff.read"

      attrs = %{
        name: "Manager",
        permissions: [valid_permission]
      }

      changeset = Role.changeset(%Role{}, attrs)
      assert changeset.valid?
    end

    test "should be invalid without required fields" do
      changeset = Role.changeset(%Role{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "should validate name length limits" do
      too_short = %{name: "A"}
      too_long = %{name: String.duplicate("A", 51)}

      short_changeset = Role.changeset(%Role{}, too_short)
      long_changeset = Role.changeset(%Role{}, too_long)

      refute short_changeset.valid?
      refute long_changeset.valid?

      assert "should be at least 2 character(s)" in errors_on(short_changeset).name
      assert "should be at most 50 character(s)" in errors_on(long_changeset).name
    end

    test "should validate permissions subset" do
      invalid_attrs = %{
        name: "Dispatcher",
        permissions: ["invalid_permission_name"]
      }

      changeset = Role.changeset(%Role{}, invalid_attrs)

      refute changeset.valid?
      assert "has an invalid entry" in errors_on(changeset).permissions
    end

    test "should enforce unique name constraint on insert" do
      insert(:role, name: "Courier")

      duplicate_changeset = Role.changeset(%Role{}, %{name: "Courier"})

      assert {:error, changeset} = Repo.insert(duplicate_changeset)
      assert "has already been taken" in errors_on(changeset).name
    end
  end
end
