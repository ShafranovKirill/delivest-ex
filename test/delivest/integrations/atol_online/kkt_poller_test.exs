defmodule Delivest.Integrations.AtolOnline.KktPollerTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Fiscal.BranchSettings
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.AtolOnline
  alias Delivest.Integrations.AtolOnline.{Kkt, KktPoller}
  alias Delivest.Integrations.Health

  @now ~U[2026-10-30 12:00:00Z]

  defp register(attrs \\ %{}) do
    Map.merge(
      %{
        "groupCode" => "group",
        "networkErrorCode" => 0,
        "fiscalStoragePercentageUse" => 40.5,
        "fiscalStorageExpiration" => "2027-10-30T00:00:00+00:00"
      },
      attrs
    )
  end

  defp branch(sandbox \\ false) do
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      fiscal: %BranchSettings{
        mode: :own,
        atol: %AtolOnline.Settings{
          login: "kkt-#{branch.id}",
          password: "secret",
          group_code: "group",
          sandbox: sandbox,
          callback_token: "t"
        }
      }
    })

    branch
  end

  defp stub_kkt(registers) do
    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      if String.ends_with?(conn.request_path, "gettoken") do
        Req.Test.json(conn, %{"token" => "tok"})
      else
        Req.Test.json(conn, %{"_embedded" => Enum.map(registers, &%{"data" => &1})})
      end
    end)
  end

  test "a healthy register has no issues" do
    assert Kkt.issues([register()], @now) == []
  end

  test "every condition is reported" do
    assert Kkt.issues([register(%{"networkErrorCode" => 2})], @now) == [:offline]
    assert Kkt.issues([register(%{"fiscalStoragePercentageUse" => 91.2})], @now) == [:fn_full]

    assert Kkt.issues(
             [register(%{"fiscalStorageExpiration" => "2026-11-15T00:00:00+00:00"})],
             @now
           ) ==
             [:fn_expiring]

    assert Kkt.issues(
             [
               register(%{
                 "unsentDocs" => 12,
                 "firstUnsetDocTimestamp" => "2026-10-30T08:00:00+00:00"
               })
             ],
             @now
           ) == [:offline]

    assert Kkt.issues(
             [
               register(%{
                 "unsentDocs" => 1,
                 "firstUnsetDocTimestamp" => "2026-10-30T11:50:00+00:00"
               })
             ],
             @now
           ) == []
  end

  test "targets skip sandbox and branches without our receipts" do
    live = branch()
    sandbox = branch(true)
    targets = KktPoller.targets()
    assert live.id in targets
    refute sandbox.id in targets
  end

  test "an issue raises the warning and a healthy register clears it" do
    branch = branch()

    stub_kkt([
      register(%{"fiscalStoragePercentageUse" => 95}),
      register(%{"groupCode" => "other"})
    ])

    assert :done = KktPoller.poll(branch.id)

    assert %{status: :warning, message: "kkt_issues:fn_full"} = Health.get(:atol, branch.id)

    stub_kkt([register()])
    assert :done = KktPoller.poll(branch.id)
    assert %{status: :ok} = Health.get(:atol, branch.id)
  end

  test "a failed request is retried by the poller" do
    branch = branch()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"errorCode" => "WrongLoginOrPassword"})
    end)

    assert {:error, _reason} = KktPoller.poll(branch.id)
  end
end
