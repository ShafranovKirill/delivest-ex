defmodule Delivest.Integrations.YandexEda.BusyModeTest do
  use Delivest.DataCase, async: true

  import Delivest.YandexEdaFixtures

  alias Delivest.Integrations.YandexEda
  alias Delivest.Integrations.YandexEda.BusyPoller

  setup do
    push_credentials()
    %{branch: yandex_branch()}
  end

  defp busy(branch, extra, till),
    do: %{
      "busy_places" => [
        %{
          "origin_id" => branch.id,
          "delivery_type" => "marketplace",
          "extra_minutes" => extra,
          "valid_till" => DateTime.to_iso8601(till)
        }
      ]
    }

  test "the high demand status is saved and dropped when it ends", %{branch: branch} do
    till = DateTime.add(DateTime.utc_now(), 3600)

    stub_push(%{
      "/partner-integration/v1/place-info/v1/busy-mode-status" => busy(branch, 15, till)
    })

    assert {:ok, 1} = BusyPoller.poll("all")
    assert_received {:push, _path, %{"origin_ids" => [origin], "limit" => 500}}
    assert origin == branch.id
    assert %{extra_minutes: 15} = YandexEda.busy_mode(branch.id)

    stub_push(%{
      "/partner-integration/v1/place-info/v1/busy-mode-status" => %{"busy_places" => []}
    })

    assert {:ok, 0} = BusyPoller.poll("all")
    assert YandexEda.busy_mode(branch.id) == nil
  end

  test "an expired status is not shown", %{branch: branch} do
    till = DateTime.add(DateTime.utc_now(), -60)

    stub_push(%{
      "/partner-integration/v1/place-info/v1/busy-mode-status" => busy(branch, 10, till)
    })

    assert {:ok, 1} = BusyPoller.poll("all")
    assert YandexEda.busy_mode(branch.id) == nil
  end
end
