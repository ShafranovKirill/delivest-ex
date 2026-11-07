defmodule Delivest.Integrations.YandexEda.StopListTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Integrations.Frontpad
  alias Delivest.Integrations.YandexEda.StopList
  alias Delivest.Net.{ProductStop, Stops}

  test "a recent sync is not repeated" do
    branch_id = Ecto.UUID.generate()
    Cachex.put(:crm_cache, {:stops, branch_id}, %{synced_at: DateTime.utc_now(:second)})

    assert :ok = StopList.refresh(branch_id)
  end

  test "an old sync runs again outside of the request process" do
    branch = insert(:branch)

    Cachex.put(:crm_cache, {:stops, branch.id}, %{
      synced_at: DateTime.add(DateTime.utc_now(), -5, :minute)
    })

    assert {:ok, :disabled} = StopList.refresh(branch.id)
  end

  test "a stale snapshot times out at the request budget and retains local stops" do
    branch = insert(:branch, is_active: true)
    product = insert_branch_product(branch.id, external_id: "101")

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Frontpad.Settings{api_key: "key", sync_stops: true}
      }
    })

    Repo.insert!(%ProductStop{
      branch_id: branch.id,
      product_id: product.id,
      source: ProductStop.manual()
    })

    Cachex.del(:stop_cache, branch.id)

    Cachex.put(:crm_cache, {:stops, branch.id}, %{
      synced_at: DateTime.add(DateTime.utc_now(), -31, :second)
    })

    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      send(test_pid, {:provider_started, self()})

      receive do
        :release -> Req.Test.json(conn, %{"result" => "success", "error" => "no_stops"})
      after
        5_000 -> Req.Test.json(conn, %{"result" => "success", "error" => "no_stops"})
      end
    end)

    started = System.monotonic_time(:millisecond)
    assert {:error, :timeout} = StopList.refresh(branch.id)
    assert System.monotonic_time(:millisecond) - started < 2_800
    assert_received {:provider_started, provider_pid}
    send(provider_pid, :release)
    assert Stops.stopped_ids(branch.id) == MapSet.new([product.id])
  end
end
