defmodule Delivest.Features.SettingsTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory

  alias Delivest.{Features, Repo}
  alias Delivest.Features.{Gate, Settings}

  setup do
    role = insert(:role, permissions: ["admin"])
    admin = insert(:staff, role: role)
    branch = insert(:branch)
    %{admin: admin, role: role, branch: branch, scope: {:branch, branch.id}}
  end

  test "only a current administrator can inspect or configure settings", %{scope: scope} do
    editor =
      insert(:staff, role: insert(:role, permissions: ["branches.update", "franchise.update"]))

    for staff <- [nil, editor] do
      refute Settings.authorized?(staff)
      assert {:error, :forbidden} = Settings.rows(staff, scope)
      assert {:error, :forbidden} = Settings.preview(staff, "segments", scope)
      assert {:error, :forbidden} = Settings.configure(staff, "segments", scope, true)
    end

    refute Features.enabled?("segments", :franchise)
  end

  test "stale admin structs cannot bypass revoked or deleted access", %{
    admin: admin,
    role: role,
    scope: scope
  } do
    role |> Ecto.Changeset.change(permissions: ["branches.update"]) |> Repo.update!()
    assert {:error, :forbidden} = Settings.configure(admin, "segments", scope, true)
    assert {:error, :forbidden} = Settings.rows(admin, scope)

    role |> Ecto.Changeset.change(permissions: ["admin"]) |> Repo.update!()
    admin |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()
    assert {:error, :forbidden} = Settings.configure(admin, "segments", scope, true)
    assert {:error, :forbidden} = Settings.preview(admin, "segments", scope)
    refute Features.enabled?("segments", :franchise)
  end

  test "allowlist and malformed or absent scopes fail closed", %{admin: admin, scope: scope} do
    gates_before = Repo.all(Gate)

    for feature <- ["unknown", "notifications", "marketing_policies", "yandex_ads", nil] do
      assert {:error, :forbidden} = Settings.configure(admin, feature, scope, true)
      assert {:error, :forbidden} = Settings.preview(admin, feature, scope)
    end

    for invalid <- [:all, "franchise", {:branch, "invalid"}, {:branch, Ecto.UUID.generate()}, nil] do
      assert {:error, :forbidden} = Settings.rows(admin, invalid)
      assert {:error, :forbidden} = Settings.configure(admin, "segments", invalid, true)
    end

    assert {:error, :forbidden} = Settings.configure(admin, "segments", :franchise, true)
    assert {:error, :forbidden} = Settings.configure(admin, "segments", scope, "true")
    assert Repo.all(Gate) == gates_before
  end

  test "deleted branches cannot be configured", %{admin: admin, branch: branch, scope: scope} do
    gates_before = Repo.all(Gate)
    branch |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()
    assert {:error, :forbidden} = Settings.rows(admin, scope)
    assert {:error, :forbidden} = Settings.configure(admin, "segments", scope, true)
    assert Repo.all(Gate) == gates_before
  end

  test "branch enable activates its parent and leaves other branches untouched", %{
    admin: admin,
    scope: scope
  } do
    other = insert(:branch)

    for feature <- Settings.branch_features() do
      assert {:ok, _} = Settings.configure(admin, feature, scope, true)
      assert Features.enabled?(feature, :franchise)
      assert Features.enabled?(feature, scope)
      refute Features.enabled?(feature, {:branch, other.id})
      refute Repo.get_by(Gate, feature: feature, scope_key: "branch:" <> other.id)
    end

    assert {:ok, rows} = Settings.rows(admin, scope)
    assert Enum.all?(rows, & &1.enabled)
    assert Enum.sort(Enum.map(rows, & &1.feature)) == Enum.sort(Settings.branch_features())

    %{rows: actors} = Repo.query!("SELECT DISTINCT actor FROM feature_audits")
    assert actors == [["staff:" <> admin.id]]
  end

  test "network controls enable dependencies without enabling every branch", %{
    admin: admin,
    scope: scope
  } do
    other = insert(:branch)

    assert {:ok, [%{feature: "analytics_franchise", enabled: false}]} =
             Settings.rows(admin, :franchise)

    assert {:ok, _} = Settings.configure(admin, "analytics_franchise", :franchise, true)
    assert Features.enabled?("analytics_franchise", :franchise)
    assert Features.enabled?("analytics_extended", :franchise)
    refute Features.enabled?("analytics_franchise", scope)

    assert {:ok, _} = Settings.configure(admin, "analytics_franchise", scope, true)
    assert Features.enabled?("analytics_franchise", scope)
    assert Features.enabled?("analytics_extended", scope)
    refute Features.enabled?("analytics_franchise", {:branch, other.id})
    refute Features.enabled?("analytics_extended", {:branch, other.id})
  end

  test "disable requires confirmation and affects only the selected branch", %{
    admin: admin,
    scope: scope
  } do
    other = insert(:branch)
    other_scope = {:branch, other.id}
    assert {:ok, _} = Settings.configure(admin, "analytics_funnel", scope, true)
    assert {:ok, _} = Settings.configure(admin, "analytics_funnel", other_scope, true)

    assert {:error, {:confirmation_required, preview}} =
             Settings.configure(admin, "analytics_funnel", scope, false)

    assert Features.enabled?("analytics_funnel", scope)
    assert {:ok, _} = Settings.configure(admin, "analytics_funnel", scope, false, preview)
    refute Features.enabled?("analytics_funnel", scope)
    assert Features.enabled?("analytics_funnel", other_scope)
    assert Features.enabled?("analytics_funnel", :franchise)
  end

  test "dependent disable previews reject stale confirmation and preserve data", %{
    admin: admin,
    scope: scope
  } do
    assert {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "host")
    assert {:ok, _} = Features.configure("marketing_policies", scope, true, actor: "host")
    assert {:ok, preview} = Settings.preview(admin, "segments", scope)
    assert preview.features == ["marketing_policies"]

    assert {:error, {:confirmation_required, ^preview}} =
             Settings.configure(admin, "segments", scope, false)

    assert {:ok, _} = Features.configure("marketing_policies", scope, false, actor: "host")
    assert {:ok, _} = Features.configure("marketing_policies", scope, true, actor: "host")

    assert {:error, {:confirmation_required, current}} =
             Settings.configure(admin, "segments", scope, false, preview)

    assert current.features == preview.features
    refute current.fingerprint == preview.fingerprint
    assert Features.enabled?("segments", scope)
    assert Features.enabled?("marketing_policies", scope)

    assert {:ok, _} = Settings.configure(admin, "segments", scope, false, current)
    refute Features.enabled?("segments", scope)
    refute Features.enabled?("marketing_policies", scope)
    assert Features.enabled?("segments", :franchise)
    assert Features.enabled?("marketing_policies", :franchise)
  end
end
