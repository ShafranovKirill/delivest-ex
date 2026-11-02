defmodule Delivest.Integrations.HealthTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.{Crm, Error, Frontpad, Health, Journal}
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Integrations.Health.Status

  defp branch(api_key) do
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Frontpad.Settings{api_key: api_key}
      }
    })

    branch
  end

  defp staff(branch, permissions) do
    staff = insert(:staff, role: insert(:role, permissions: permissions))
    insert(:staff_branch, staff: staff, branch: branch)
    staff
  end

  defp stub(response), do: Req.Test.stub(Delivest.HTTP.Client, &Req.Test.json(&1, response))

  test "a successful check is saved and journaled for the branch" do
    branch = branch("key")
    stub(%{"result" => "success", "error" => "no_stops"})

    assert {:ok, %Status{status: :ok, message: nil}} = Health.check(:frontpad, branch.id)
    assert %Status{status: :ok} = Health.get(:frontpad, branch.id)
    assert [%{url: url}] = Journal.list(:frontpad, branch.id)
    assert url =~ "get_stops"
  end

  test "rejected credentials mean reconnect, other errors mean no connection" do
    branch = branch("key")

    stub(%{"result" => "error", "error" => "invalid_secret"})
    assert {:ok, %Status{status: :auth}} = Health.check(:frontpad, branch.id)

    Req.Test.stub(Delivest.HTTP.Client, &Req.Test.transport_error(&1, :timeout))
    assert {:ok, %Status{status: :failed}} = Health.check(:frontpad, branch.id)

    assert Repo.aggregate(Status, :count) == 1
    assert %{"frontpad" => %Status{status: :failed}} = Health.for_branch(branch.id)
  end

  test "an unconfigured integration fails without a request" do
    branch = branch(nil)

    assert {:ok, %Status{status: :failed, message: ":not_configured"}} =
             Health.check(:frontpad, branch.id)

    assert Journal.list(:frontpad, branch.id) == []
    assert {:error, :unknown_provider} = Health.check(:nope, branch.id)
  end

  test "auth failures and recovery" do
    branch_id = Ecto.UUID.generate()
    {:ok, _status} = Health.auth_failed(:frontpad, branch_id, {:frontpad, "invalid_secret"})
    assert %Status{status: :auth} = Health.get(:frontpad, branch_id)

    Health.recovered(:frontpad, branch_id)
    assert %Status{status: :ok, message: nil} = Health.get(:frontpad, branch_id)
  end

  test "statuses without a branch are shared" do
    {:ok, _status} = Health.auth_failed(:yandex_eda, nil, :invalid_client)
    {:ok, _status} = Health.auth_failed(:yandex_eda, nil, :invalid_client)

    assert Repo.aggregate(Status, :count) == 1
    assert %{"yandex_eda" => %Status{status: :auth}} = Health.for_branch(Ecto.UUID.generate())
  end

  test "the common error contract" do
    assert Error.classify({:http_error, 401, %{}}) == :auth
    assert Error.classify({:http_error, 403, %{}}) == :auth
    assert Error.classify({:http_error, 429, %{}}) == {:snooze, 60}
    assert Error.classify({:http_error, 502, %{}}) == :retry
    assert Error.classify({:http_error, 422, %{}}) == :permanent
    assert Error.classify({:connection_error, "timeout", :timeout}) == :retry
    assert Frontpad.classify_error({:frontpad, "invalid_secret"}) == :auth
    assert Frontpad.classify_error({:frontpad, "requests_limit"}) == {:snooze, 60}
  end

  test "a settings-only provider has no connection check" do
    assert Health.checkable?(:frontpad)
    assert Health.checkable?(:yookassa)
    refute Health.checkable?(:zvonok)

    assert {:error, :not_checkable} = Health.check(:zvonok, nil)
    assert Health.get(:zvonok, nil) == nil
  end

  test "a manual check needs integrations.update and access to the branch" do
    branch = branch("key")
    other_branch = insert(:branch)
    reader = staff(branch, ["integrations.read"])
    editor = staff(branch, ["integrations.update"])
    stranger = staff(other_branch, ["integrations.update"])

    Req.Test.stub(Delivest.HTTP.Client, fn _conn ->
      flunk("the external API must not be called")
    end)

    refute Health.checkable_for?(reader, :frontpad, branch.id)
    refute Health.checkable_for?(stranger, :frontpad, branch.id)
    assert Health.checkable_for?(editor, :frontpad, branch.id)

    assert {:error, :forbidden} = Health.check_as(reader, :frontpad, branch.id)
    assert {:error, :forbidden} = Health.check_as(stranger, :frontpad, branch.id)
    assert Health.get(:frontpad, branch.id) == nil
    assert Journal.list(:frontpad, branch.id) == []
  end

  test "shared settings need an administrator" do
    branch = branch("key")
    editor = staff(branch, ["integrations.read", "integrations.update"])

    refute Health.checkable_for?(editor, :yookassa, branch.id)
    assert {:error, :forbidden} = Health.check_as(editor, :yookassa, nil)
  end

  test "an administrator checks the shared settings" do
    admin = insert(:staff, role: build(:role, permissions: ["admin"]))

    Repo.insert!(%Delivest.Integrations.Yookassa.Settings{
      shop_id: "shop",
      secret_key: "secret"
    })

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{"account_id" => "account"})
    end)

    assert Health.checkable_for?(admin, :yookassa, nil)
    assert {:ok, %Status{status: :ok}} = Health.check_as(admin, :yookassa, nil)
  end

  test "a warning keeps the connection result and is cleared without it" do
    branch = branch("key")
    stub(%{"result" => "success", "error" => "no_stops"})
    assert {:ok, %Status{status: :ok}} = Health.check(:frontpad, branch.id)

    assert {:ok, _status} = Health.warn(:frontpad, branch.id, "catalog_issues:2")

    assert %Status{status: :ok, warning: "catalog_issues:2", checked_at: %DateTime{}} =
             Health.get(:frontpad, branch.id)

    assert :ok = Health.clear_warning(:frontpad, branch.id)

    assert %Status{status: :ok, warning: nil, checked_at: %DateTime{}} =
             Health.get(:frontpad, branch.id)
  end

  test "a warning can live together with a failed connection" do
    branch = branch("key")

    assert {:ok, %Status{status: :failed}} =
             Health.report(:frontpad, branch.id, Frontpad, {:error, :timeout})

    assert {:ok, _status} = Health.warn(:frontpad, branch.id, "catalog_issues:2")

    assert %Status{status: :failed, checked_at: %DateTime{}, warning: "catalog_issues:2"} =
             Health.get(:frontpad, branch.id)
  end

  test "successful saves reset the previous check only when credentials changed" do
    branch = branch("key")
    staff = insert(:staff, role: build(:role, permissions: ["admin"]))
    assert {:ok, %Status{status: :ok}} = Health.report(:frontpad, branch.id, Frontpad, :ok)

    assert {:ok, _crm} =
             Crm.update_branch_settings(staff, branch.id, %{
               "enabled" => true,
               "provider" => "frontpad",
               "frontpad" => %{"api_key" => "key"}
             })

    assert %Status{status: :ok} = Health.get(:frontpad, branch.id)

    assert {:ok, _crm} =
             Crm.update_branch_settings(staff, branch.id, %{"enabled" => false})

    assert %Status{status: :ok} = Health.get(:frontpad, branch.id)

    assert {:ok, _crm} =
             Crm.update_branch_settings(staff, branch.id, %{
               "enabled" => true,
               "provider" => "frontpad",
               "frontpad" => %{"api_key" => "new-key"}
             })

    assert %Status{status: nil, checked_at: nil} = Health.get(:frontpad, branch.id)
  end

  test "changing credentials drops the result but keeps an independent warning" do
    branch = branch("key")
    staff = insert(:staff, role: build(:role, permissions: ["admin"]))
    assert {:ok, %Status{status: :ok}} = Health.report(:frontpad, branch.id, Frontpad, :ok)
    assert {:ok, _status} = Health.warn(:frontpad, branch.id, "catalog_issues:1")

    assert {:ok, _crm} =
             Crm.update_branch_settings(staff, branch.id, %{
               "enabled" => true,
               "provider" => "frontpad",
               "frontpad" => %{"api_key" => "new-key"}
             })

    assert %Status{status: nil, checked_at: nil, warning: "catalog_issues:1"} =
             Health.get(:frontpad, branch.id)
  end

  test "a failed save does not reset the previous check" do
    branch = branch("key")
    staff = insert(:staff, role: build(:role, permissions: ["admin"]))
    assert {:ok, %Status{status: :ok}} = Health.report(:frontpad, branch.id, Frontpad, :ok)

    assert {:error, %Ecto.Changeset{}} =
             Crm.update_branch_settings(staff, branch.id, %{
               "enabled" => true,
               "provider" => "iiko",
               "iiko" => %{"api_key" => ""}
             })

    assert %Status{status: :ok} = Health.get(:frontpad, branch.id)
  end
end
