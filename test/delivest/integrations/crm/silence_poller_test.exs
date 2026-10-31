defmodule Delivest.Integrations.Crm.SilencePollerTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.{BranchSettings, SilencePoller}
  alias Delivest.Integrations.Frontpad
  alias Delivest.Oms.Order

  setup do
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      delivery_time: 40,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Frontpad.Settings{api_key: "key", webhook_token: "token"}
      }
    })

    %{branch: branch}
  end

  defp sent_order(branch, minutes_ago, crm_attrs \\ %{}) do
    sent_at = DateTime.add(DateTime.utc_now(:second), -minutes_ago, :minute)

    crm =
      struct(
        %Order.CrmSync{provider: "frontpad", status: "sent", sent_at: sent_at},
        crm_attrs
      )

    branch.id
    |> order_fixture()
    |> Ecto.Changeset.change(
      status: :accepted,
      fulfillment_type: :delivery,
      inserted_at: sent_at,
      crm: crm
    )
    |> Repo.update!()
  end

  test "targets are the branches with Frontpad", %{branch: branch} do
    assert branch.id in SilencePoller.targets()
  end

  test "an order silent past its deadline gets an alert", %{branch: branch} do
    order = sent_order(branch, 120)

    assert :done = SilencePoller.poll(branch.id)
    assert Crm.alert?(Repo.reload!(order))
  end

  test "an order inside its deadline is left alone", %{branch: branch} do
    order = sent_order(branch, 20)

    SilencePoller.poll(branch.id)
    refute Crm.alert?(Repo.reload!(order))
  end

  test "a recent status change keeps the order quiet", %{branch: branch} do
    recent = DateTime.add(DateTime.utc_now(:second), -5, :minute)
    order = sent_order(branch, 120, %{remote_status: "preparing", remote_status_at: recent})

    SilencePoller.poll(branch.id)
    refute Crm.alert?(Repo.reload!(order))
  end

  test "an acknowledged alert is not raised again on an order that already has one", %{
    branch: branch
  } do
    order = sent_order(branch, 120, %{alert: "check"})

    SilencePoller.poll(branch.id)
    assert Repo.reload!(order).crm.alert == "check"
  end
end
