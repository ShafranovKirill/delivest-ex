defmodule DelivestWeb.Staff.IntegrationLive.PresentationTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.{Frontpad, Health}
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Integrations.Iiko
  alias DelivestWeb.Staff.IntegrationLive.Presentation

  defp branch(crm \\ %BranchSettings{}, extra \\ %{}) do
    branch = insert(:branch, name: "North")

    info =
      %BranchInfo{branch_id: branch.id, crm: crm}
      |> struct(extra)
      |> Repo.insert!()

    %{branch | info: info}
  end

  defp crm(attrs) do
    struct(%BranchSettings{enabled: true, provider: :frontpad, sources: ["app"]}, attrs)
  end

  defp usage(state, label) do
    Enum.find(state.usage, &(&1.label == label))
  end

  test "saved keys, a passed check and real sending are independent" do
    branch =
      branch(
        crm(%{
          enabled: false,
          provider: nil,
          frontpad: %Frontpad.Settings{api_key: "key"}
        })
      )

    assert {:ok, _status} = Health.report(:frontpad, branch.id, Frontpad, :ok)

    state = Presentation.state(:frontpad, branch)

    assert state.credentials.state == :complete
    assert state.connection.state == :ok

    sending = usage(state, "Sending new orders")
    assert sending.state == :off
    assert sending.detail =~ "New orders are not sent"
  end

  test "empty sources stop new orders even when sending is on" do
    branch =
      branch(
        crm(%{
          sources: [],
          frontpad: %Frontpad.Settings{api_key: "key"}
        })
      )

    state = Presentation.state(:frontpad, branch)

    assert state.credentials.state == :complete
    assert state.connection.state == :unchecked

    sending = usage(state, "Sending new orders")
    assert sending.state == :not_ready
    assert sending.detail =~ "No order sources selected"

    sources = usage(state, "Order sources")
    assert sources.state == :off
    assert sources.detail == "No order sources selected"
  end

  test "another active crm is named instead of pretending to send" do
    branch =
      branch(
        crm(%{
          provider: :iiko,
          iiko: %Iiko.Settings{api_key: "key"},
          frontpad: %Frontpad.Settings{api_key: "key"}
        })
      )

    state = Presentation.state(:frontpad, branch)

    assert state.credentials.state == :complete

    sending = usage(state, "Sending new orders")
    assert sending.state == :off
    assert sending.detail == "Sending to Frontpad: off. Selected CRM: iiko"
  end

  test "missing credential fields are listed separately from the connection" do
    branch =
      branch(
        crm(%{
          provider: :iiko,
          iiko: %Iiko.Settings{api_key: "key"}
        })
      )

    state = Presentation.state(:iiko, branch)

    assert state.credentials.state == :partial
    assert state.credentials.filled == 1
    assert state.credentials.total == 3
    assert state.credentials.missing == ["Organization", "Terminal group"]
    assert state.connection.state == :unchecked
  end

  test "a warning does not replace the connection result" do
    branch = branch(crm(%{frontpad: %Frontpad.Settings{api_key: "key"}}))

    assert {:ok, _status} = Health.report(:frontpad, branch.id, Frontpad, :ok)
    assert {:ok, _status} = Health.warn(:frontpad, branch.id, "catalog_issues:3")

    state = Presentation.state(:frontpad, branch)

    assert state.connection.state == :ok
    assert [%{text: text}] = state.warnings
    assert text == "The menu differs from the CRM: 3"

    assert :ok = Health.clear_warning(:frontpad, branch.id)
    assert Presentation.state(:frontpad, branch).warnings == []
  end

  test "a warning alone never looks like a checked connection" do
    branch = branch(crm(%{frontpad: %Frontpad.Settings{api_key: "key"}}))

    assert {:ok, _status} = Health.warn(:frontpad, branch.id, "kkt_issues:fn_full")

    state = Presentation.state(:frontpad, branch)

    assert state.connection.state == :unchecked
    assert [%{text: text}] = state.warnings
    assert text =~ "fiscal storage"
  end

  test "the scope says whether the integration is shared or belongs to the branch" do
    branch = branch()

    assert Presentation.scope(:yookassa, branch) == {:network, nil}
    assert Presentation.scope_text(Presentation.scope(:yookassa, branch)) == "All branches"

    assert Presentation.scope(:yandex_eda, branch) == {:network, "North"}
    assert Presentation.scope_text(Presentation.scope(:yandex_eda, branch)) =~ "North"

    assert Presentation.scope(:frontpad, branch) == {:branch, "North"}
    assert Presentation.scope_text(Presentation.scope(:frontpad, branch)) == "Branch: North"
  end

  test "capabilities remain separate from connection and branch usage" do
    branch = branch()
    state = Presentation.state(:frontpad, branch)

    assert state.connection.state == :unchecked
    assert Enum.find(state.usage, &(&1.label == "Sending new orders")).state == :off
    assert {"Import full menu", false, true, true} in state.capabilities
    assert {"Catalog for product matching", true, true, true} in state.capabilities

    assert {"Order item edits", false} in Presentation.state(:yandex_eda, branch).capabilities
    assert {"Promotions", false} in Presentation.state(:yandex_eda, branch).capabilities
    assert {"Combos", false} in Presentation.state(:yandex_eda, branch).capabilities
  end
end
