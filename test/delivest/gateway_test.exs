defmodule Delivest.GatewayTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Gateway
  alias Delivest.Identity.Branch.BranchInfo

  defp branch(crm) do
    branch = insert(:branch)
    Repo.insert!(%BranchInfo{branch_id: branch.id, crm: crm})
    Repo.preload(branch, :info, force: true)
  end

  defp areas(crm), do: crm |> branch() |> Gateway.mode() |> Map.fetch!(:areas)

  test "a branch without crm owns everything" do
    mode = Gateway.mode(branch(nil))

    assert mode.provider == nil
    assert Enum.all?(Map.values(mode.areas), &(&1 == :own))
    assert Map.keys(mode.areas) |> Enum.sort() == Enum.sort(Gateway.areas())
  end

  test "a disabled crm changes nothing" do
    refute branch(%{enabled: false, provider: :iiko}) |> Gateway.active?()
  end

  test "frontpad takes the kitchen and statuses, the rest stays ours" do
    areas = areas(%{enabled: true, provider: :frontpad, frontpad: %{api_key: "key"}})

    assert %{kitchen: :crm, statuses: :crm, pos: :own, couriers: :own, receipts: :own} = areas
    assert areas.stops == :crm
    assert areas.menu == :own
  end

  test "iiko with its own cash desk and delivery takes them too" do
    areas = areas(%{enabled: true, provider: :iiko, menu_source: :crm})

    assert %{kitchen: :crm, statuses: :crm, pos: :crm, couriers: :crm, receipts: :crm} = areas
    assert %{menu: :crm, stops: :crm} = areas
  end

  test "r_keeper follows the same matrix as iiko" do
    areas = areas(%{enabled: true, provider: :rkeeper, menu_source: :own})

    assert %{kitchen: :crm, pos: :crm, couriers: :crm, receipts: :crm, menu: :own} = areas
  end

  test "the mode names the provider" do
    mode = Gateway.mode(branch(%{enabled: true, provider: :iiko}))

    assert mode.provider == :iiko
    assert mode.name == "iiko"
    assert Gateway.crm?(branch(%{enabled: true, provider: :iiko}), :kitchen)
  end
end
