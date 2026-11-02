defmodule Delivest.Loyalty.PolicyTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory

  alias Delivest.Franchise.SettingsStore
  alias Delivest.Identity.Branch.{BranchInfo, LoyaltySettings}
  alias Delivest.Loyalty
  alias Delivest.Oms.Order
  alias Delivest.Repo

  setup do
    Cachex.clear(:franchise_cache)
    on_exit(fn -> Cachex.clear(:franchise_cache) end)

    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      loyalty: %LoyaltySettings{enabled: true, per_rubles: 1000, stars: 999, expire_days: 999}
    })

    %{branch: branch}
  end

  test "the rate and expiry come from the franchise", %{branch: branch} do
    {:ok, _settings} =
      SettingsStore.save(%{
        loyalty_per_rubles: 50,
        loyalty_stars: 3,
        loyalty_expire_days: 30
      })

    settings = Loyalty.settings(branch)

    assert %LoyaltySettings{
             enabled: true,
             per_rubles: 50,
             stars: 3,
             expire_days: 30
           } = settings

    order = %Order{total_amount: 25_000, delivery_amount: 0}
    assert Loyalty.stars_for(order, settings) == 15
  end

  test "a branch cannot override the franchise policy", %{branch: branch} do
    {:ok, _settings} = SettingsStore.save(%{loyalty_per_rubles: 50, loyalty_stars: 3})
    {:ok, _branch} = update_info(branch, %{"per_rubles" => "1", "stars" => "1"})

    assert %LoyaltySettings{per_rubles: 50, stars: 3} = Loyalty.settings(branch.id)
  end

  defp update_info(branch, changes) do
    BranchInfo
    |> Repo.get_by!(branch_id: branch.id)
    |> BranchInfo.changeset(%{"loyalty" => changes})
    |> Repo.update()
    |> tap(fn _result -> Cachex.clear(:branch_cache) end)
  end
end
