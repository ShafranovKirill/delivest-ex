defmodule Delivest.Integrations.YandexEda.StopListTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Integrations.YandexEda.StopList

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
end
