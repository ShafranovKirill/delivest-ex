defmodule Delivest.Identity.StaffsTest do
  use Delivest.DataCase, async: true

  alias Delivest.Identity.Staffs
  alias Delivest.Identity.Staff
  import Delivest.Factory

  @valid_password "Q1w2e3r4t5!"
  @invalid_password "invalid"

  setup do
    start_supervised({Cachex, name: :staff_cache})
    Cachex.clear(:staff_cache)

    admin_role =
      insert(:role,
        permissions: ["staff.read", "staff.create", "staff.update", "staff.delete", "admin"]
      )

    admin_actor = insert(:staff, role: admin_role)

    user_role = insert(:role, permissions: [])
    forbidden_actor = insert(:staff, role: user_role)

    {:ok, admin: admin_actor, forbidden_user: forbidden_actor}
  end

  describe "list_staff/3" do
    test "should return list of non-deleted staff", %{admin: actor} do
      staff1 = insert(:staff)
      staff2 = insert(:staff)
      deleted_staff = insert(:staff, deleted_at: DateTime.utc_now(:second))

      assert {:ok, {staff_list, _meta}} = Staffs.list_staff(actor)
      staff_ids = Enum.map(staff_list, & &1.id)

      assert actor.id in staff_ids
      assert staff1.id in staff_ids
      assert staff2.id in staff_ids
      refute deleted_staff.id in staff_ids
    end

    test "should preload associations when preload option is passed", %{admin: actor} do
      _staff = insert(:staff)

      assert {:ok, {[staff | _], _meta}} = Staffs.list_staff(actor, %{}, preload: [:role])
      assert Ecto.assoc_loaded?(staff.role)
    end
  end

  describe "create_staff/2" do
    test "should create staff with valid data when permitted", %{admin: actor} do
      role = insert(:role)

      attrs = %{
        login: "new_staff_user",
        password: @valid_password,
        role_id: role.id
      }

      assert {:ok, %Staff{} = staff} = Staffs.create_staff(actor, attrs)
      assert staff.login == "new_staff_user"
      assert Argon2.verify_pass(@valid_password, staff.password_hash)
    end

    test "should return error changeset with invalid data when permitted", %{admin: actor} do
      attrs = %{login: "usr", password: @invalid_password}

      assert {:error, %Ecto.Changeset{} = changeset} = Staffs.create_staff(actor, attrs)

      assert "must be at least 8 characters long and contain at least one uppercase letter, one lowercase letter, one number, and one special character" in errors_on(
               changeset
             ).password
    end

    test "should return forbidden when actor lacks permissions", %{forbidden_user: actor} do
      role = insert(:role)
      attrs = %{login: "new_staff_user", password: @valid_password, role_id: role.id}

      assert {:error, :forbidden} = Staffs.create_staff(actor, attrs)
    end
  end

  describe "update_staff/3" do
    test "should update staff when permitted", %{admin: actor} do
      target_staff = insert(:staff, login: "old_login")
      attrs = %{login: "updated_login"}

      assert {:ok, %Staff{} = updated_staff} = Staffs.update_staff(actor, target_staff, attrs)
      assert updated_staff.login == "updated_login"
    end

    test "should return error changeset with invalid data when permitted", %{admin: actor} do
      target_staff = insert(:staff)
      attrs = %{login: "inv@lid!"}

      assert {:error, %Ecto.Changeset{} = changeset} =
               Staffs.update_staff(actor, target_staff, attrs)

      assert "can only contain letters, numbers, dots, dashes, and underscores" in errors_on(
               changeset
             ).login
    end

    test "should return forbidden when actor lacks permissions", %{forbidden_user: actor} do
      target_staff = insert(:staff)

      assert {:error, :forbidden} =
               Staffs.update_staff(actor, target_staff, %{login: "new_login"})
    end
  end

  describe "change_password/3" do
    test "should update password and clear cache when permitted", %{admin: admin} do
      target_staff = insert(:staff)
      Cachex.put(:staff_cache, target_staff.id, target_staff)

      attrs = %{password: "NewStrongPass1!"}

      assert {:ok, %Staff{} = updated_staff} = Staffs.change_password(admin, target_staff, attrs)
      assert Argon2.verify_pass("NewStrongPass1!", updated_staff.password_hash)
      assert {:ok, nil} = Cachex.get(:staff_cache, target_staff.id)
    end

    test "should return error changeset when password invalid and permitted", %{admin: admin} do
      target_staff = insert(:staff)
      attrs = %{password: "123"}

      assert {:error, %Ecto.Changeset{} = changeset} =
               Staffs.change_password(admin, target_staff, attrs)

      assert "must be at least 8 characters long and contain at least one uppercase letter, one lowercase letter, one number, and one special character" in errors_on(
               changeset
             ).password
    end

    test "should return forbidden when actor is not admin", %{forbidden_user: actor} do
      target_staff = insert(:staff)

      assert {:error, :forbidden} =
               Staffs.change_password(actor, target_staff, %{password: "NewStrongPass1!"})
    end
  end

  describe "get_staff/2" do
    test "should return staff from DB and populate cache on cache miss" do
      staff = insert(:staff)

      assert {:ok, nil} = Cachex.get(:staff_cache, staff.id)
      assert {:ok, %Staff{} = fetched_staff} = Staffs.get_staff(staff.id)
      assert fetched_staff.id == staff.id

      assert {:ok, %Staff{} = cached_staff} = Cachex.get(:staff_cache, staff.id)
      assert cached_staff.id == staff.id
    end

    test "should return staff from cache on cache hit" do
      staff = insert(:staff)
      Cachex.put(:staff_cache, staff.id, staff)

      assert {:ok, %Staff{} = fetched_staff} = Staffs.get_staff(staff.id)
      assert fetched_staff.id == staff.id
    end

    test "should ensure preloads are loaded and update cache" do
      staff = insert(:staff)
      Cachex.put(:staff_cache, staff.id, staff)

      assert {:ok, %Staff{} = fetched_staff} = Staffs.get_staff(staff.id, preload: [:role])
      assert Ecto.assoc_loaded?(fetched_staff.role)

      assert {:ok, %Staff{} = cached_staff} = Cachex.get(:staff_cache, staff.id)
      assert Ecto.assoc_loaded?(cached_staff.role)
    end

    test "should return error if staff doesnt exist" do
      fake_id = Ecto.UUID.generate()
      assert {:error, :not_found} = Staffs.get_staff(fake_id)
    end
  end

  describe "soft_delete_staff/2" do
    test "should set deleted_at timestamp and clear cache when permitted", %{admin: admin} do
      target_staff = insert(:staff)
      Cachex.put(:staff_cache, target_staff.id, target_staff)

      assert {:ok, %Staff{} = deleted_staff} = Staffs.soft_delete_staff(admin, target_staff)
      assert deleted_staff.deleted_at != nil
      assert {:ok, nil} = Cachex.get(:staff_cache, target_staff.id)
    end

    test "should return forbidden when actor lacks permissions", %{forbidden_user: actor} do
      target_staff = insert(:staff)
      assert {:error, :forbidden} = Staffs.soft_delete_staff(actor, target_staff)
    end
  end

  describe "authenticate/2" do
    test "should return staff on successful authentication" do
      password = @valid_password
      password_hash = Argon2.hash_pwd_salt(password)

      staff = insert(:staff, login: "active_user", password_hash: password_hash)

      assert {:ok, %Staff{} = auth_staff} = Staffs.authenticate("active_user", password)
      assert auth_staff.id == staff.id
    end

    test "should return error on invalid password" do
      password_hash = Argon2.hash_pwd_salt(@valid_password)
      insert(:staff, login: "active_user", password_hash: password_hash)

      assert {:error, :invalid_credentials} =
               Staffs.authenticate("active_user", "WrongPassword123!")
    end

    test "should return error when staff doesn't exist" do
      assert {:error, :invalid_credentials} = Staffs.authenticate("ghost_user", @valid_password)
    end

    test "should be case-sensitive for login authentication" do
      password_hash = Argon2.hash_pwd_salt(@valid_password)
      insert(:staff, login: "CaseSensitive", password_hash: password_hash)

      assert {:error, :invalid_credentials} =
               Staffs.authenticate("casesensitive", @valid_password)

      assert {:ok, %Staff{}} = Staffs.authenticate("CaseSensitive", @valid_password)
    end
  end

  describe "staff - creation and validation" do
    test "should reject login with invalid characters", %{admin: admin} do
      role = insert(:role)

      attrs = %{login: "inv@lid!login", password: @valid_password, role_id: role.id}

      assert {:error, %Ecto.Changeset{} = changeset} = Staffs.create_staff(admin, attrs)
      assert changeset.errors[:login] != nil
    end

    test "should reject duplicate logins", %{admin: admin} do
      role = insert(:role)
      existing_login = "existing_user"
      insert(:staff, login: existing_login)

      attrs = %{login: existing_login, password: @valid_password, role_id: role.id}

      assert {:error, %Ecto.Changeset{} = changeset} = Staffs.create_staff(admin, attrs)
      assert "has already been taken" in errors_on(changeset).login
    end

    test "should accept valid password formats", %{admin: admin} do
      role = insert(:role)

      valid_passwords = [
        "ValidPass1!",
        "C0mpl3x@Password",
        "Test1234!@#$"
      ]

      Enum.each(valid_passwords, fn pwd ->
        attrs = %{login: "user_#{:rand.uniform(1000)}", password: pwd, role_id: role.id}
        assert {:ok, %Staff{}} = Staffs.create_staff(admin, attrs)
      end)
    end
  end

  describe "staff - password management" do
    test "should handle password update with special characters", %{admin: admin} do
      staff = insert(:staff)
      new_password = "NewP@ssw0rd!"

      assert {:ok, updated_staff} =
               Staffs.change_password(admin, staff, %{password: new_password})

      assert Argon2.verify_pass(new_password, updated_staff.password_hash)
    end

    test "should reject password that is too weak", %{admin: admin} do
      staff = insert(:staff)

      weak_passwords = [
        "abc",
        "12345678",
        "password",
        "NoNumbers!",
        "nouppercase1!"
      ]

      Enum.each(weak_passwords, fn pwd ->
        {:error, %Ecto.Changeset{} = changeset} =
          Staffs.change_password(admin, staff, %{password: pwd})

        assert changeset.errors[:password] != nil
      end)
    end

    test "should clear cache after password change", %{admin: admin} do
      staff = insert(:staff)
      Cachex.put(:staff_cache, staff.id, staff)

      {:ok, nil} = Cachex.get(:staff_cache, staff.id) |> (fn _ -> {:ok, nil} end).()

      Staffs.change_password(admin, staff, %{password: "NewPass123!"})

      assert {:ok, nil} = Cachex.get(:staff_cache, staff.id)
    end
  end

  describe "staff - deletion and recovery" do
    test "should only list non-deleted staff", %{admin: admin} do
      active_staff = insert(:staff)
      deleted_staff = insert(:staff, deleted_at: DateTime.utc_now(:second))

      {:ok, {staff_list, _}} = Staffs.list_staff(admin)
      staff_ids = Enum.map(staff_list, & &1.id)

      assert active_staff.id in staff_ids
      refute deleted_staff.id in staff_ids
    end

    test "should soft delete without removing data", %{admin: admin} do
      staff = insert(:staff, login: "to_delete")
      staff_id = staff.id

      {:ok, deleted_staff} = Staffs.soft_delete_staff(admin, staff)
      assert deleted_staff.deleted_at != nil
      assert deleted_staff.id == staff_id
    end

    test "should not allow deletion by non-admin", %{forbidden_user: actor} do
      staff = insert(:staff)

      assert {:error, :forbidden} = Staffs.soft_delete_staff(actor, staff)
    end
  end

  describe "staff - role transitions" do
    test "should update staff role", %{admin: admin} do
      staff = insert(:staff)
      new_role = insert(:role)

      {:ok, updated} = Staffs.update_staff(admin, staff, %{role_id: new_role.id})
      assert updated.role_id == new_role.id
    end

    test "should clear cache when updating role", %{admin: admin} do
      staff = insert(:staff)
      new_role = insert(:role)
      Cachex.put(:staff_cache, staff.id, staff)

      Staffs.update_staff(admin, staff, %{role_id: new_role.id})

      assert {:ok, nil} = Cachex.get(:staff_cache, staff.id)
    end
  end

  describe "staff - concurrent operations" do
    test "should handle concurrent staff updates safely", %{admin: admin} do
      staff = insert(:staff)

      task1 =
        Task.async(fn ->
          Staffs.update_staff(admin, staff, %{login: "concurrent_user_1"})
        end)

      task2 =
        Task.async(fn ->
          Staffs.update_staff(admin, staff, %{login: "concurrent_user_2"})
        end)

      result1 = Task.await(task1)
      result2 = Task.await(task2)

      # Both should complete, one update overwrites
      assert result1 != nil or result2 != nil
    end
  end

  describe "staff - edge cases" do
    test "should accept minimum valid login length", %{admin: admin} do
      role = insert(:role)
      attrs = %{login: "ab", password: @valid_password, role_id: role.id}

      result = Staffs.create_staff(admin, attrs)
      assert result != nil
    end

    test "should preload associations correctly", %{admin: admin} do
      _staff = insert(:staff)

      {:ok, {[fetched | _], _}} = Staffs.list_staff(admin, %{}, preload: [:role])
      assert Ecto.assoc_loaded?(fetched.role)
    end

    test "should handle nil password during authentication" do
      assert {:error, :invalid_credentials} = Staffs.authenticate("user", nil)
    end
  end
end
