defmodule Delivest.Integrations.HealthTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.{Error, Frontpad, Health, Journal}
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
    assert Error.classify({:connection_error, "timeout"}) == :retry
    assert Frontpad.classify_error({:frontpad, "invalid_secret"}) == :auth
    assert Frontpad.classify_error({:frontpad, "requests_limit"}) == {:snooze, 60}
  end
end
