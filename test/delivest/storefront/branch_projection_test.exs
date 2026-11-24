defmodule Delivest.Storefront.BranchProjectionTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Franchise.Settings, as: FranchiseSettings
  alias Delivest.Repo
  alias Delivest.Storefront.BranchProjection
  alias Delivest.Integrations.Health.Status
  alias Delivest.Integrations.Yookassa
  alias Delivest.Integrations.Yookassa.Settings
  alias DelivestWeb.Client.Branch.BranchJSON

  test "branch preparation reads a fixed number of times and JSON rendering reads none" do
    branches =
      for n <- 1..30 do
        branch = insert(:branch, is_active: true, slug: "projection-#{n}")
        Repo.insert!(%BranchInfo{branch_id: branch.id, city: "City #{n}"})
        branch
      end

    loaded = Repo.preload(branches, :info, force: true)

    counts =
      for size <- [1, 3, 30] do
        Cachex.clear(:franchise_cache)

        {count, prepared} =
          count_queries(fn -> BranchProjection.prepare(Enum.take(loaded, size)) end)

        Cachex.clear(:franchise_cache)
        {render_count, %{data: data}} = count_queries(fn -> BranchJSON.index(prepared) end)
        assert render_count == 0
        assert length(data) == size
        assert Enum.all?(data, &match?(%{branch_info: %{city: _}}, &1))
        assert Enum.all?(data, &match?(%{branch_info: %{timezone: "Europe/Moscow"}}, &1))
        count
      end

    assert Enum.uniq(counts) |> length() == 1
    assert hd(counts) <= 4
  end

  test "prepared online payment readiness matches the legacy global check" do
    branch = insert(:branch, is_active: true)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      payments: %Delivest.Identity.Branch.PaymentSettings{online: true}
    })

    loaded = Repo.preload(branch, :info, force: true)
    assert Yookassa.ready_snapshot?() == Yookassa.ready?()

    assert BranchJSON.show(BranchProjection.prepare([loaded]) |> Map.put(:branch, loaded)).data.branch_info.payment_methods ==
             [:cash, :card_offline]

    Repo.insert!(%Settings{shop_id: "123", secret_key: "secret"})
    Repo.insert!(%Status{provider: "yookassa", status: :ok, checked_at: DateTime.utc_now()})

    assert Yookassa.ready_snapshot?() == Yookassa.ready?()

    assert BranchJSON.show(BranchProjection.prepare([loaded]) |> Map.put(:branch, loaded)).data.branch_info.payment_methods ==
             [:cash, :card_offline, :online]
  end

  test "projection uses fresh franchise settings for maintenance, timezone and loyalty" do
    branch = insert(:branch, is_active: true)
    Repo.insert!(%BranchInfo{branch_id: branch.id})

    (Repo.one(FranchiseSettings) || %FranchiseSettings{})
    |> FranchiseSettings.changeset(%{
      timezone: "Asia/Yekaterinburg",
      maintenance_enabled: true,
      loyalty_per_rubles: 250,
      loyalty_stars: 9,
      loyalty_expire_days: 45
    })
    |> Repo.insert_or_update!()

    Cachex.put(:franchise_cache, :settings, %FranchiseSettings{
      timezone: "Europe/Moscow",
      maintenance_enabled: false,
      loyalty_per_rubles: 100,
      loyalty_stars: 5,
      loyalty_expire_days: 180
    })

    on_exit(fn -> Cachex.del(:franchise_cache, :settings) end)
    loaded = Repo.preload(branch, :info, force: true)
    {prepare_count, prepared} = count_queries(fn -> BranchProjection.prepare([loaded]) end)
    {render_count, %{data: [data]}} = count_queries(fn -> BranchJSON.index(prepared) end)

    assert prepare_count <= 4
    assert render_count == 0
    assert data.branch_info.maintenance == %{enabled: true, reason: :franchise}
    assert data.branch_info.timezone == "Asia/Yekaterinburg"
    assert data.branch_info.loyalty.per_rubles == 250
    assert data.branch_info.loyalty.stars == 9
    assert data.branch_info.loyalty.expire_days == 45
  end

  defp count_queries(fun) do
    id = "branch-projection-#{System.unique_integer([:positive])}"
    pid = self()

    :ok =
      :telemetry.attach(
        id,
        [:delivest, :repo, :query],
        fn _event, _measurements, _metadata, _config ->
          if self() == pid, do: send(pid, {:query, id})
        end,
        nil
      )

    result =
      try do
        fun.()
      after
        :ok = :telemetry.detach(id)
      end

    {drain(id, 0), result}
  end

  defp drain(id, count) do
    receive do
      {:query, ^id} -> drain(id, count + 1)
    after
      0 -> count
    end
  end
end
