defmodule Delivest.Integrations.IikoContractTest do
  use Delivest.DataCase, async: false

  alias Delivest.Integrations.Iiko

  @moduletag :contract
  @moduletag :iiko_contract

  setup do
    config = Application.get_env(:delivest, Delivest.HTTP.Client)
    Application.put_env(:delivest, Delivest.HTTP.Client, req_options: [retry: false])
    on_exit(fn -> Application.put_env(:delivest, Delivest.HTTP.Client, config) end)

    %{
      settings: %Iiko.Settings{
        api_key: System.fetch_env!("IIKO_API_KEY"),
        organization_id: System.get_env("IIKO_ORGANIZATION_ID"),
        terminal_group_id: System.get_env("IIKO_TERMINAL_GROUP_ID")
      }
    }
  end

  test "organizations, terminal groups, payment types and stops are read", %{settings: settings} do
    assert {:ok, [%{id: org} | _] = organizations} = Iiko.organizations(settings)
    IO.puts("iiko organizations: #{inspect(organizations)}")
    ids = Enum.map(organizations, & &1.id)

    assert {:ok, groups} = Iiko.terminal_groups(settings, ids)
    IO.puts("iiko terminal groups: #{inspect(groups)}")
    assert {:ok, %{payment_types: types}} = Iiko.dictionaries(settings, ids)
    IO.puts("iiko payment types: #{inspect(types)}")

    settings = %{settings | organization_id: settings.organization_id || org}
    assert {:ok, products} = Iiko.fetch_catalog(settings)
    IO.puts("iiko products: #{length(products)}")
  end
end
